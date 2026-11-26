# =============================================================================
# EKS CLUSTER — reusable, instantiated twice
# =============================================================================
# One module for both the Backstage and Argo Workflows clusters. They differ
# only in name, instance type and scaling, so the difference lives in the
# caller's variables rather than in two near-identical copies of this code.
#
# Issue #5 requires: one small managed node group, IRSA (OIDC provider), core
# add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI).
# =============================================================================

data "aws_partition" "current" {}

locals {
  # Add-ons that every cluster gets. EBS CSI is conditional.
  base_addons = {
    vpc-cni    = {}
    coredns    = {}
    kube-proxy = {}
  }
  addons = var.enable_ebs_csi ? merge(local.base_addons, { aws-ebs-csi-driver = {} }) : local.base_addons
}

# --- Control plane IAM -------------------------------------------------------
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# --- Cluster -----------------------------------------------------------------
# EKS creates /aws/eks/<name>/cluster itself the first time logging is enabled, with
# no retention and no tags, and Terraform never learns it exists — so it survives
# destroy and keeps logs forever. Creating it first makes Terraform the owner, and
# EKS simply writes into it.
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, { Name = "${var.cluster_name}-logs" })
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
  }

  # API mode rather than the legacy aws-auth ConfigMap. Access entries are the
  # current mechanism and are manageable from Terraform; editing aws-auth by
  # hand is how clusters become un-reproducible.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Audit and authenticator logs are what you need when access breaks. The
  # others are noisy and chargeable; left off deliberately for a demo.
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = merge(var.tags, { Name = var.cluster_name })

  # The log group must exist first, or EKS creates its own unmanaged one.
  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]
}

# --- IRSA --------------------------------------------------------------------
# AC: "A test pod in the Backstage cluster can read/write the TechDocs bucket
# through IRSA, with no static AWS keys." This provider is what makes that
# possible — without it, pods can only use node instance credentials.
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  tags = merge(var.tags, { Name = "${var.cluster_name}-oidc" })
}

# --- Node group IAM ----------------------------------------------------------
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
    # Lets nodes be managed by SSM Session Manager instead of SSH + a bastion.
    "AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

# --- Node group --------------------------------------------------------------
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types = var.instance_types
  disk_size      = var.disk_size_gb
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  # The autoscaler (if added later) owns desired_size. Without this, every
  # apply would fight it back to the configured value.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-ng" })

  depends_on = [aws_iam_role_policy_attachment.node]
}

# --- Add-ons -----------------------------------------------------------------
# Created after the node group: CoreDNS has no nodes to schedule on before it
# and would sit degraded.
resource "aws_eks_addon" "this" {
  for_each = local.addons

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # EBS CSI needs IRSA to call the EC2 API for volume operations.
  service_account_role_arn = each.key == "aws-ebs-csi-driver" ? aws_iam_role.ebs_csi[0].arn : null

  tags = var.tags

  depends_on = [aws_eks_node_group.this]
}

# --- EBS CSI IRSA role -------------------------------------------------------
data "aws_iam_policy_document" "ebs_csi_assume" {
  count = var.enable_ebs_csi ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  count = var.enable_ebs_csi ? 1 : 0

  name               = "${var.cluster_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count = var.enable_ebs_csi ? 1 : 0

  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

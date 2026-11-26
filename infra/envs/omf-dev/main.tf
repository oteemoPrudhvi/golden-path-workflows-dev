# =============================================================================
# ROOT MODULE — one deployment of the IDX platform
# =============================================================================
# Wires the seven modules together. Contains no resource definitions of its
# own beyond the account guard: everything is a module instantiation, so the
# same code stands up a second client from a different tfvars file.
# =============================================================================

provider "aws" {
  region = var.region

  # Applied to every resource that supports tagging, so individual modules
  # do not each have to remember. AC #14.
  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}

locals {
  # The single place client and environment become a resource name prefix.
  # Modules never see 'omf' — they receive this string.
  name_prefix = "${var.client}-${var.environment}"

  common_tags = {
    project      = var.project
    environment  = var.environment
    owner        = var.owner
    client       = var.client
    "managed-by" = "terraform"
  }

  backstage_cluster_name = "${local.name_prefix}-backstage"
  argo_cluster_name      = "${local.name_prefix}-argo"
}

# --- Account guard -----------------------------------------------------------
# Fails the plan if credentials point at the wrong account. See the variable
# description for why this exists.
resource "terraform_data" "account_guard" {
  input = var.allowed_account_id

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.allowed_account_id
      error_message = "Wrong AWS account. Credentials are for ${data.aws_caller_identity.current.account_id}, this configuration expects ${var.allowed_account_id}. Check AWS_PROFILE."
    }
  }
}

# --- Network -----------------------------------------------------------------
module "network" {
  source = "../../modules/network"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = true

  # Both cluster names are needed up front so the subnets carry the
  # kubernetes.io/cluster/<name> tags the ALB controller discovers them by.
  eks_cluster_names = [
    local.backstage_cluster_name,
    local.argo_cluster_name,
  ]

  tags = local.common_tags
}

# --- Clusters ----------------------------------------------------------------
# Same module twice. The clusters differ only in name and sizing.
module "backstage_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name       = local.backstage_cluster_name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = module.network.private_subnet_ids

  instance_types = var.backstage_node_instance_types
  desired_size   = var.backstage_node_desired
  min_size       = 1
  max_size       = var.backstage_node_desired + 1

  public_access_cidrs = var.cluster_public_access_cidrs
  log_retention_days  = var.log_retention_days

  tags = local.common_tags
}

module "argo_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name       = local.argo_cluster_name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = module.network.private_subnet_ids

  instance_types = var.argo_node_instance_types
  desired_size   = var.argo_node_desired
  min_size       = 1
  max_size       = var.argo_node_max

  public_access_cidrs = var.cluster_public_access_cidrs
  log_retention_days  = var.log_retention_days

  tags = local.common_tags
}

# --- Database ----------------------------------------------------------------
module "database" {
  source = "../../modules/rds-postgres"

  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id
  subnet_ids  = module.network.private_subnet_ids

  # Only the Backstage cluster. The Argo cluster has no reason to reach the
  # portal's database, and granting it would be the easy default.
  allowed_security_groups = {
    backstage = module.backstage_cluster.cluster_security_group_id
  }

  instance_class       = var.db_instance_class
  allocated_storage_gb = var.db_allocated_storage_gb

  log_retention_days = var.log_retention_days

  tags = local.common_tags
}

# --- Backstage supporting resources ------------------------------------------
module "backstage_support" {
  source = "../../modules/backstage-support"

  name_prefix       = local.name_prefix
  oidc_provider_arn = module.backstage_cluster.oidc_provider_arn
  oidc_provider_url = module.backstage_cluster.oidc_provider_url

  tags = local.common_tags
}

# --- Load balancer controllers -----------------------------------------------
# One per cluster. Without these nothing creates an ALB from an Ingress, which
# is why ACs #6, #7 and #8 were unachievable before review caught it.
module "backstage_alb_controller" {
  source = "../../modules/alb-controller"

  cluster_name      = local.backstage_cluster_name
  oidc_provider_arn = module.backstage_cluster.oidc_provider_arn
  oidc_provider_url = module.backstage_cluster.oidc_provider_url

  tags = local.common_tags
}

module "argo_alb_controller" {
  source = "../../modules/alb-controller"

  cluster_name      = local.argo_cluster_name
  oidc_provider_arn = module.argo_cluster.oidc_provider_arn
  oidc_provider_url = module.argo_cluster.oidc_provider_url

  tags = local.common_tags
}

# --- Argo supporting resources -----------------------------------------------
module "argo_support" {
  source = "../../modules/argo-support"

  name_prefix       = local.name_prefix
  oidc_provider_arn = module.argo_cluster.oidc_provider_arn
  oidc_provider_url = module.argo_cluster.oidc_provider_url

  tags = local.common_tags
}

# --- Scoped AWS access for the golden-path provisioning workflow (issue #57) --
module "golden_path_access" {
  source = "../../modules/golden-path-access"

  name_prefix       = local.name_prefix
  oidc_provider_arn = module.argo_cluster.oidc_provider_arn
  oidc_provider_url = module.argo_cluster.oidc_provider_url

  # Named people who may test the golden-path Terraform with the same scope as the workflow.
  developer_session_names = var.golden_path_developers

  tags = local.common_tags
}

# --- Ingress / TLS -----------------------------------------------------------
# The restriction applies to the whole internet, and the clusters are part of
# it: a pod in the Backstage cluster calling the Argo ALB leaves through the NAT
# gateway. Allow that address too, or restricting the UI breaks the Scaffolder's
# handoff to Argo. Empty stays empty — "unrestricted" must remain visible.
locals {
  argo_inbound_cidrs = length(var.argo_inbound_cidrs) == 0 ? [] : concat(
    var.argo_inbound_cidrs,
    [for ip in module.network.nat_public_ips : "${ip}/32"],
  )
}

module "ingress_tls" {
  source = "../../modules/ingress-tls"

  name_prefix        = local.name_prefix
  domain_name        = var.domain_name
  create_hosted_zone = var.create_hosted_zone
  argo_inbound_cidrs = local.argo_inbound_cidrs

  # ExternalDNS runs in the Backstage cluster and writes the Route 53 records
  # pointing at whatever ALB the controller created.
  oidc_provider_arn = module.backstage_cluster.oidc_provider_arn
  oidc_provider_url = module.backstage_cluster.oidc_provider_url

  tags = local.common_tags
}

# --- CI role -----------------------------------------------------------------
module "github_oidc" {
  source = "../../modules/github-oidc"

  name_prefix          = local.name_prefix
  github_org           = var.github_org
  github_repo          = var.github_repo
  allowed_refs         = var.github_allowed_refs
  allowed_environments = var.github_allowed_environments
  subject_prefix       = var.github_subject_prefix

  create_oidc_provider       = var.github_create_oidc_provider
  existing_oidc_provider_arn = var.github_existing_oidc_provider_arn

  ecr_repository_arns = [module.backstage_support.ecr_repository_arn]

  # Built TechDocs are published here by CI (docs/ workflow); the portal reads them.
  techdocs_bucket_arns = [module.backstage_support.techdocs_bucket_arn]

  # Both clusters: CI deploys Backstage to one and Argo manifests to the
  # other. DescribeCluster only — in-cluster authorisation comes from an
  # access entry, not from IAM.
  eks_cluster_arns = [
    module.backstage_cluster.cluster_arn,
    module.argo_cluster.cluster_arn,
  ]

  tags = local.common_tags
}

# --- EKS access entries for CI -----------------------------------------------
# AC #12 asks for a role that can deploy. eks:DescribeCluster alone only gets
# CI a kubeconfig — every kubectl call then returns Unauthorized, because
# authorisation inside the cluster comes from an access entry, not from IAM.
# Caught in review; the role was assumable but useless.
#
# EKS access entries are the current mechanism and keep Kubernetes permissions
# in Kubernetes, where they can be scoped per namespace rather than being an
# IAM blunt instrument.
resource "aws_eks_access_entry" "ci_backstage" {
  cluster_name  = module.backstage_cluster.cluster_name
  principal_arn = module.github_oidc.role_arn
  type          = "STANDARD"
  tags          = local.common_tags
}

resource "aws_eks_access_policy_association" "ci_backstage" {
  cluster_name  = module.backstage_cluster.cluster_name
  principal_arn = module.github_oidc.role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  # Edit, not admin, and namespace-scoped. CI deploys the application; it has
  # no reason to modify cluster-wide resources.
  access_scope {
    type       = "namespace"
    namespaces = [var.backstage_namespace]
  }

  depends_on = [aws_eks_access_entry.ci_backstage]
}

resource "aws_eks_access_entry" "ci_argo" {
  cluster_name  = module.argo_cluster.cluster_name
  principal_arn = module.github_oidc.role_arn
  type          = "STANDARD"
  tags          = local.common_tags
}

resource "aws_eks_access_policy_association" "ci_argo" {
  cluster_name  = module.argo_cluster.cluster_name
  principal_arn = module.github_oidc.role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [var.argo_namespace]
  }

  depends_on = [aws_eks_access_entry.ci_argo]
}

# --- Adopting log groups that already exist --------------------------------------
# Only when adopt_existing_log_groups is true (see the variable). One block per group
# because each targets a fixed address; the empty for_each is what makes it a no-op on
# a fresh account.
import {
  for_each = var.adopt_existing_log_groups ? toset(["backstage"]) : toset([])
  to       = module.backstage_cluster.aws_cloudwatch_log_group.cluster
  id       = "/aws/eks/${local.backstage_cluster_name}/cluster"
}

import {
  for_each = var.adopt_existing_log_groups ? toset(["argo"]) : toset([])
  to       = module.argo_cluster.aws_cloudwatch_log_group.cluster
  id       = "/aws/eks/${local.argo_cluster_name}/cluster"
}

# Only `postgresql` is adopted: RDS has not run an upgrade yet, so the `upgrade` group
# does not exist and Terraform simply creates it (adopting it would be an error).
import {
  for_each = var.adopt_existing_log_groups ? toset(["postgresql"]) : toset([])
  to       = module.database.aws_cloudwatch_log_group.exports["postgresql"]
  id       = "/aws/rds/instance/${local.name_prefix}-backstage/postgresql"
}

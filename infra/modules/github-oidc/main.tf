# =============================================================================
# GITHUB ACTIONS OIDC — keyless CI credentials
# =============================================================================
# AC #11: "The GitHub Actions OIDC role can be assumed from this repo's
# workflows and has only the permissions needed (ECR push, EKS deploy)."
#
# This is the one identity in the stack where least privilege genuinely
# matters. A human operator running Terraform as admin is a contained risk —
# they are present and accountable. A CI role is assumed automatically by
# whatever code reaches the branch, so its blast radius is whatever the
# policy allows.
#
# No static access keys anywhere. GitHub presents a short-lived OIDC token,
# AWS exchanges it for temporary credentials, and nothing is stored.
# =============================================================================

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn

  # What GitHub puts in front of every subject for this repository. See the
  # subject_prefix variable: the classic form is silently wrong when the
  # repository issues immutable subject claims.
  subject_prefix = coalesce(var.subject_prefix, "repo:${var.github_org}/${var.github_repo}")

  # Subject claims this role will accept. Branch refs plus, optionally,
  # GitHub Environments.
  branch_subjects = [
    for ref in var.allowed_refs :
    "${local.subject_prefix}:ref:${ref}"
  ]

  environment_subjects = [
    for env in var.allowed_environments :
    "${local.subject_prefix}:environment:${env}"
  ]

  allowed_subjects = concat(local.branch_subjects, local.environment_subjects)
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS has verified this issuer's certificate chain natively since mid-2023,
  # so the thumbprint is no longer load-bearing. Kept because the API still
  # requires the field.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = merge(var.tags, { Name = "${var.name_prefix}-github-oidc" })
}

# --- Trust policy ------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # StringEquals, not StringLike. A wildcard here is how a fork's pull
    # request ends up holding deploy credentials.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.allowed_subjects
    }
  }
}

# --- Permissions -------------------------------------------------------------
data "aws_iam_policy_document" "permissions" {
  # ECR auth token is account-wide by design — the API takes no resource.
  # Push itself is restricted to named repositories below.
  statement {
    sid       = "EcrGetAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.ecr_repository_arns) > 0 ? [1] : []
    content {
      sid    = "EcrPush"
      effect = "Allow"
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:CompleteLayerUpload",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
      ]
      resources = var.ecr_repository_arns
    }
  }

  # Publishing built documentation. Same actions the portal's own role holds on this
  # bucket, so the pipeline can write what the portal reads. Scoped to the named
  # buckets only; the object statement covers keys, the list statement the bucket.
  dynamic "statement" {
    for_each = length(var.techdocs_bucket_arns) > 0 ? [1] : []
    content {
      sid    = "TechDocsPublishObjects"
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
      ]
      resources = [for arn in var.techdocs_bucket_arns : "${arn}/*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.techdocs_bucket_arns) > 0 ? [1] : []
    content {
      sid       = "TechDocsPublishList"
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = var.techdocs_bucket_arns
    }
  }

  # DescribeCluster only. This is what `aws eks update-kubeconfig` needs.
  # Authorisation for anything inside the cluster comes from an EKS access
  # entry bound to this role, not from IAM — which keeps Kubernetes
  # permissions in Kubernetes where they can be scoped per namespace.
  dynamic "statement" {
    for_each = length(var.eks_cluster_arns) > 0 ? [1] : []
    content {
      sid       = "EksDescribeForKubeconfig"
      effect    = "Allow"
      actions   = ["eks:DescribeCluster"]
      resources = var.eks_cluster_arns
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.name_prefix}-github-actions"
  description        = "Assumed by GitHub Actions in ${var.github_org}/${var.github_repo} via OIDC"
  assume_role_policy = data.aws_iam_policy_document.assume.json

  # A CI role should hold credentials for minutes, not hours. The workflow
  # re-assumes on each job, so a short ceiling costs nothing and limits how
  # long a leaked token stays useful.
  max_session_duration = 3600

  tags = merge(var.tags, { Name = "${var.name_prefix}-github-actions" })
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${var.name_prefix}-github-actions-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.permissions.json
}

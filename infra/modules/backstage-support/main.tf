# =============================================================================
# BACKSTAGE SUPPORTING RESOURCES
# =============================================================================
# TechDocs S3 bucket + IRSA role, ECR repository, Secrets Manager placeholders.
#
# AC: "A test pod in the Backstage cluster can read/write the TechDocs bucket
# through IRSA, with no static AWS keys."
# =============================================================================

data "aws_caller_identity" "current" {}

# --- TechDocs bucket ---------------------------------------------------------
# The scaffolded app uses the `local` TechDocs publisher, which stores
# generated docs on the pod filesystem. That dies with the pod and is not
# shared between replicas, so a bucket is required for any real deployment.
resource "aws_s3_bucket" "techdocs" {
  bucket = "${var.name_prefix}-techdocs-${data.aws_caller_identity.current.account_id}"
  tags   = merge(var.tags, { Name = "${var.name_prefix}-techdocs" })
}

resource "aws_s3_bucket_public_access_block" "techdocs" {
  bucket                  = aws_s3_bucket.techdocs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "techdocs" {
  bucket = aws_s3_bucket.techdocs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Docs are regenerated from source on every build, so versioning would pay to
# store history that git already holds.
resource "aws_s3_bucket_versioning" "techdocs" {
  bucket = aws_s3_bucket.techdocs.id
  versioning_configuration {
    status = "Suspended"
  }
}

# --- IRSA role for the Backstage pod -----------------------------------------
data "aws_iam_policy_document" "techdocs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    # Scoped to one service account in one namespace. Without the sub
    # condition any pod in the cluster could assume this role.
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.service_account_namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "techdocs_access" {
  statement {
    sid    = "TechDocsObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.techdocs.arn}/*"]
  }

  statement {
    sid       = "TechDocsListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.techdocs.arn]
  }

  # Read-only on the secrets this deployment owns. Backstage reads them at
  # startup; it never writes them.
  statement {
    sid    = "ReadOwnSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = ["arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:${var.name_prefix}/backstage/*"]
  }
}

resource "aws_iam_role" "backstage" {
  name               = "${var.name_prefix}-backstage-irsa"
  assume_role_policy = data.aws_iam_policy_document.techdocs_assume.json
  tags               = merge(var.tags, { Name = "${var.name_prefix}-backstage-irsa" })
}

resource "aws_iam_role_policy" "backstage" {
  name   = "${var.name_prefix}-backstage-access"
  role   = aws_iam_role.backstage.id
  policy = data.aws_iam_policy_document.techdocs_access.json
}

# --- ECR ---------------------------------------------------------------------
resource "aws_ecr_repository" "backstage" {
  name                 = "${var.name_prefix}/backstage"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # Demo repository — destroy should not fail because images remain.
  force_delete = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-backstage-ecr" })
}

# AC: ECR repository "with a lifecycle policy". Untagged layers accumulate on
# every build and are pure cost once superseded.
resource "aws_ecr_lifecycle_policy" "backstage" {
  repository = aws_ecr_repository.backstage.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.ecr_untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.ecr_untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the most recent ${var.ecr_tagged_image_count} tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_tagged_image_count
        }
        action = { type = "expire" }
      },
    ]
  })
}

# --- Secret placeholders -----------------------------------------------------
# Containers only. Values are set out of band — never in Terraform code, state
# or a plan file. AC #10.
resource "aws_secretsmanager_secret" "app" {
  for_each = toset(var.additional_secret_keys)

  name                    = "${var.name_prefix}/backstage/${each.value}"
  description             = "Backstage ${each.value} — value set out of band, not by Terraform"
  recovery_window_in_days = 0

  tags = merge(var.tags, { Name = "${var.name_prefix}-backstage-${each.value}" })
}

# --- External Secrets Operator IRSA ------------------------------------------
# Issue #5 scope item 5: secrets "surfaced to pods via External Secrets".
#
# Terraform creates the secret containers above. This role is what lets the
# operator read them, so an ExternalSecret can project them into a Kubernetes
# Secret the Backstage pod mounts. Without it, Backstage has no database
# credentials and will not start.
#
# Separate from the Backstage pod role deliberately. The operator reads every
# secret under the prefix; the application should only read its own. Merging
# them would hand the application the operator's breadth.
data "aws_iam_policy_document" "external_secrets_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.external_secrets_namespace}:${var.external_secrets_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "external_secrets" {
  # Read-only, and only under this deployment's prefix. The operator never
  # writes secrets.
  statement {
    sid    = "ReadDeploymentSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = ["arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:${var.name_prefix}/*"]
  }

  # ListSecrets takes no resource — the API is account-wide by design. The
  # operator needs it to resolve secret names to ARNs.
  statement {
    sid       = "ListSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:ListSecrets"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${var.name_prefix}-external-secrets-irsa"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_assume.json
  tags               = merge(var.tags, { Name = "${var.name_prefix}-external-secrets-irsa" })
}

resource "aws_iam_role_policy" "external_secrets" {
  name   = "${var.name_prefix}-external-secrets-access"
  role   = aws_iam_role.external_secrets.id
  policy = data.aws_iam_policy_document.external_secrets.json
}

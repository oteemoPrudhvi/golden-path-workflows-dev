# =============================================================================
# ARGO WORKFLOWS SUPPORTING RESOURCES
# =============================================================================
# Issue #5 scope item 4 requires an "artifact repository bucket" for the Argo
# cluster. AC #9 then checks that a hello-world workflow runs to Succeeded
# AND stores its artifact there.
#
# Separate bucket from TechDocs: different lifecycle (artifacts are disposable,
# docs are regenerated on build), different writers, different cluster.
# =============================================================================

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.name_prefix}-argo-artifacts-${data.aws_caller_identity.current.account_id}"
  tags   = merge(var.tags, { Name = "${var.name_prefix}-argo-artifacts" })

  # Demo bucket — destroy should not fail because workflow runs left objects
  # behind. AC #16 requires clean teardown.
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Workflow artifacts and archived logs accumulate on every run and have no
# value once the run is forgotten. Without this the bucket grows forever.
resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-workflow-artifacts"
    status = "Enabled"

    filter {}

    expiration {
      days = var.artifact_expiry_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# --- IRSA for workflow pods and the controller -------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    # StringEquals against an explicit list of service account subjects —
    # an allowlist, not a pattern. The comment here previously said
    # StringLike, which the code never did; corrected after review.
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values = [
        for sa in var.workflow_service_accounts :
        "system:serviceaccount:${var.argo_namespace}:${sa}"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "artifacts_access" {
  statement {
    sid    = "WorkflowArtifactObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }

  statement {
    sid       = "WorkflowArtifactListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn]
  }
}

resource "aws_iam_role" "workflows" {
  name               = "${var.name_prefix}-argo-workflows-irsa"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = merge(var.tags, { Name = "${var.name_prefix}-argo-workflows-irsa" })
}

resource "aws_iam_role_policy" "workflows" {
  name   = "${var.name_prefix}-argo-artifacts-access"
  role   = aws_iam_role.workflows.id
  policy = data.aws_iam_policy_document.artifacts_access.json
}

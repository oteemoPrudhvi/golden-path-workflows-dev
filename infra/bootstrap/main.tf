# =============================================================================
# TERRAFORM STATE BACKEND
# =============================================================================
# Creates the S3 bucket that all other root modules use for remote state.
#
# Run once, before anything else:
#   cd infra/bootstrap && terraform init && terraform apply
#
# Locking uses S3 native locking (use_lockfile) rather than a DynamoDB table.
# Issue #5 permits either. Native locking means one less resource to create,
# pay for and forget to clean up — which matches the "size for cost" steer.
# It requires Terraform >= 1.11.
# =============================================================================

locals {
  common_tags = {
    client       = var.client
    project      = var.project
    environment  = var.environment
    owner        = var.owner
    "managed-by" = "terraform"
  }

  state_bucket_name = "${var.name_prefix}-tfstate-${data.aws_caller_identity.current.account_id}"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket_name

  # The state bucket outlives every environment. Deleting it orphans all
  # infrastructure Terraform knows about, so destroying it must be deliberate.
  # AC: "terraform destroy on dev cleanly removes everything it created
  # (apart from intentionally retained state bucket)."
  lifecycle {
    prevent_destroy = true
  }
}

# AC: versioning on. Lets a corrupted or truncated state be rolled back.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# AC: encryption on.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# State can contain sensitive values even when secrets are kept out of code.
# Nothing about this bucket should ever be public.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Old state versions accumulate forever otherwise. 90 days is enough to
# recover from a bad apply without paying to store years of history.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

# Reject any plaintext PutObject. Defence in depth alongside the SSE default.
resource "aws_s3_bucket_policy" "state_tls_only" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.state.arn,
          "${aws_s3_bucket.state.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.state]
}

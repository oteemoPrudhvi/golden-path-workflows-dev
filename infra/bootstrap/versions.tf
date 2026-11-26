# Bootstrap uses LOCAL state on purpose. It creates the bucket that every other
# root module stores its state in, so it cannot store its own state there.
#
# The generated terraform.tfstate for this module should be committed to the
# repo OR kept somewhere durable — it is the only record of the state bucket.
# It contains no secrets.

terraform {
  # S3 native state locking (use_lockfile) requires >= 1.11, which is what the
  # dev root module uses. Pinned here too so the toolchain is consistent.
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # The range is deliberate; .terraform.lock.hcl is committed and pins the
      # exact build and checksums. That is the mechanism that stops a provider
      # upgrade changing a plan nobody touched.
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

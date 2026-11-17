terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 6.0"
    }
  }

  # Bucket, region and key are supplied by the workflow at init time:
  #   -backend-config=bucket=...  -backend-config=region=...
  #   -backend-config=key=python-packages/<package_name>/terraform.tfstate
  # One state file per package, so packages never affect each other.
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

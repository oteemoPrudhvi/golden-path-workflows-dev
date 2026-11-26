# Partial backend configuration.
#
# The bucket name contains the AWS account id, which is not known until the
# bootstrap module has run — and backend blocks cannot reference variables.
# So the values live in backend.hcl (gitignored) and are supplied at init:
#
#   terraform init -backend-config=backend.hcl
#
# See backend.hcl.example and the README.
terraform {
  backend "s3" {
    key          = "envs/omf-dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

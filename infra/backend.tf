# Partial backend configuration.
#
# Backend blocks cannot reference variables, and the state key differs per
# package, so the Argo workflow supplies every value at init time:
#
#   terraform init \
#     -backend-config=bucket=<state bucket> \
#     -backend-config=region=<region> \
#     -backend-config=key=golden-path/packages/<package_name>/terraform.tfstate
#
# One state file per package, so packages never affect each other.
# For a local run, copy backend.hcl.example to backend.hcl and add the key
# with -backend-config="key=...". See the README.
terraform {
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

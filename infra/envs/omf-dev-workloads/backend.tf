# Same bucket as the infrastructure state, different key. Partial config —
# see backend.hcl.example.
terraform {
  backend "s3" {
    key          = "envs/omf-dev-workloads/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

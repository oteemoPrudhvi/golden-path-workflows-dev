# tflint configuration — AC #1 requires tflint to pass in CI for every module.

config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# The AWS ruleset catches provider-specific mistakes that `terraform validate`
# cannot: invalid instance types, malformed ARNs, deprecated arguments.
plugin "aws" {
  enabled = true
  version = "0.44.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

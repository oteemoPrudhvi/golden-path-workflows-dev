output "state_bucket" {
  description = "Name of the S3 bucket holding Terraform state. Goes into envs/dev/backend.tf."
  value       = aws_s3_bucket.state.id
}

output "region" {
  description = "Region the state bucket lives in."
  value       = var.region
}

output "backend_config_snippet" {
  description = "Paste-ready backend block for a root module."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.state.id}"
        key          = "envs/dev/terraform.tfstate"
        region       = "${var.region}"
        encrypt      = true
        use_lockfile = true
      }
    }
  EOT
}

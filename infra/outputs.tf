# The workflow reads these three outputs with `terraform output -raw`.

output "codeartifact_domain" {
  description = "CodeArtifact domain name."
  value       = module.repository.domain
}

output "codeartifact_repository" {
  description = "CodeArtifact repository name."
  value       = module.repository.repository
}

# The workflow requires a non-empty value, so a marker is returned when publishing is off.
output "publish_role_arn" {
  description = "ARN of the GitHub OIDC publish role."
  value       = local.publish_enabled ? module.publish_role[0].role_arn : "publishing-disabled"
}

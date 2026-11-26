output "provisioner_role_arn" {
  description = "Role the provisioning workflow runs as. Annotate the ServiceAccount with it."
  value       = aws_iam_role.provisioner.arn
}

output "provisioner_subject" {
  description = "The single ServiceAccount subject allowed to assume the provisioner role."
  value       = local.provisioner_subject
}

output "boundary_policy_arn" {
  description = "Permission boundary every created role must carry. Pass it to the role module as permissions_boundary."
  value       = aws_iam_policy.boundary.arn
}

output "developer_role_arn" {
  description = "Role named developers assume to test the Terraform, or null when none are listed."
  value       = local.create_developer_role ? aws_iam_role.developer[0].arn : null
}

output "resource_prefix" {
  description = "Required name prefix for roles, CodeArtifact domains and repositories."
  value       = var.resource_prefix
}

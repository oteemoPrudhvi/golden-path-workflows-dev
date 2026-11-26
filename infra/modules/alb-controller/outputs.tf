output "role_arn" {
  description = "IRSA role ARN for the controller's service account."
  value       = aws_iam_role.this.arn
}

output "service_account_name" {
  description = "Service account name the Helm release must use."
  value       = var.service_account_name
}

output "namespace" {
  description = "Namespace the controller runs in."
  value       = var.namespace
}

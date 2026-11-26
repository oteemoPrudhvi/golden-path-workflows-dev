output "techdocs_bucket" {
  description = "TechDocs bucket name, for app-config techdocs.publisher."
  value       = aws_s3_bucket.techdocs.id
}

output "techdocs_bucket_arn" {
  description = "TechDocs bucket ARN."
  value       = aws_s3_bucket.techdocs.arn
}

output "irsa_role_arn" {
  description = <<-EOT
    IRSA role ARN for the Backstage service account.

    Goes on the Kubernetes ServiceAccount as:
      eks.amazonaws.com/role-arn: <this value>
  EOT
  value       = aws_iam_role.backstage.arn
}

output "service_account_annotation" {
  description = "Paste-ready ServiceAccount annotation."
  value       = "eks.amazonaws.com/role-arn: ${aws_iam_role.backstage.arn}"
}

output "ecr_repository_arn" {
  description = "ECR repository ARN — used to scope the CI role's push permission to this repository only."
  value       = aws_ecr_repository.backstage.arn
}

output "ecr_repository_url" {
  description = "ECR repository URL for the Backstage image."
  value       = aws_ecr_repository.backstage.repository_url
}

output "secret_arns" {
  description = "ARNs of the placeholder secrets. ARNs only — no values."
  value       = { for k, v in aws_secretsmanager_secret.app : k => v.arn }
}

output "external_secrets_role_arn" {
  description = <<-EOT
    IRSA role for External Secrets Operator.

    Annotates the operator's service account so it can read Secrets Manager
    without static credentials.
  EOT
  value       = aws_iam_role.external_secrets.arn
}

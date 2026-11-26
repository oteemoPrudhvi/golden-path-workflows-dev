output "artifacts_bucket" {
  description = "S3 bucket for workflow artifacts and archived logs. Goes in the Argo artifactRepository config."
  value       = aws_s3_bucket.artifacts.id
}

output "artifacts_bucket_arn" {
  description = "Artifacts bucket ARN."
  value       = aws_s3_bucket.artifacts.arn
}

output "irsa_role_arn" {
  description = <<-EOT
    IRSA role for the Argo controller and workflow pods.

    Annotate the service accounts with:
      eks.amazonaws.com/role-arn: <this value>
  EOT
  value       = aws_iam_role.workflows.arn
}

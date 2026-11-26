output "role_arn" {
  description = <<-EOT
    Role ARN for the GitHub Actions workflow.

    Used as:
      permissions:
        id-token: write
      steps:
        - uses: aws-actions/configure-aws-credentials@v4
          with:
            role-to-assume: <this value>
            aws-region: us-east-1
  EOT
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "Role name — needed when creating the EKS access entry for CI."
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN, whether created here or passed in."
  value       = local.oidc_provider_arn
}

output "allowed_subjects" {
  description = <<-EOT
    Exact OIDC subject claims this role accepts.

    Surfaced as an output because it is the security boundary and should be
    reviewable without reading the policy JSON. If a workflow gets
    "not authorized to perform sts:AssumeRoleWithWebIdentity", compare the
    sub claim in the failing run against this list — the mismatch is almost
    always a branch that is not on it.
  EOT
  value       = local.allowed_subjects
}

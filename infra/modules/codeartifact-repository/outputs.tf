output "repository" {
  description = "Repository name."
  value       = aws_codeartifact_repository.this.repository
}

output "arn" {
  description = "Repository ARN."
  value       = aws_codeartifact_repository.this.arn
}

output "domain" {
  description = "Domain name."
  value       = aws_codeartifact_repository.this.domain
}

output "domain_owner" {
  description = "Account ID that owns the domain."
  value       = aws_codeartifact_repository.this.domain_owner
}

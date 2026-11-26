output "endpoint" {
  description = "Instance endpoint, host:port."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname only."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port."
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Initial database name."
  value       = aws_db_instance.this.db_name
}

output "security_group_id" {
  description = "Security group guarding the instance."
  value       = aws_security_group.this.id
}

output "credentials_secret_arn" {
  description = <<-EOT
    Secrets Manager ARN holding the connection details.

    The ARN, not the credentials. AC #10: no secrets in Terraform outputs in
    plaintext. External Secrets resolves this at runtime inside the cluster.
  EOT
  value       = aws_secretsmanager_secret.db.arn
}

output "credentials_secret_name" {
  description = "Secrets Manager secret name, for the ExternalSecret manifest."
  value       = aws_secretsmanager_secret.db.name
}

output "log_group_names" {
  description = "The CloudWatch log groups Terraform owns for the database's exported logs."
  value       = sort([for g in aws_cloudwatch_log_group.exports : g.name])
}

output "log_group_retention_days" {
  description = "Retention applied to those log groups."
  value       = var.log_retention_days
}

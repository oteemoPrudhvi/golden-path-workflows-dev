output "cluster_arn" {
  description = "Cluster ARN — used to scope eks:DescribeCluster on the CI role."
  value       = aws_eks_cluster.this.arn
}

output "cluster_name" {
  description = "Cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA cert for kubeconfig."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Cluster security group — used by RDS to allow only this cluster."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "IRSA OIDC provider ARN."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "IRSA OIDC issuer URL, without the https:// prefix."
  value       = replace(aws_iam_openid_connect_provider.this.url, "https://", "")
}

output "node_role_arn" {
  description = "Node group IAM role ARN."
  value       = aws_iam_role.node.arn
}

output "kubeconfig_command" {
  description = "Command to add this cluster to your kubeconfig."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${data.aws_region.current.region}"
}

data "aws_region" "current" {}

output "log_group_name" {
  description = "The CloudWatch log group Terraform owns for this cluster's control-plane logs."
  value       = aws_cloudwatch_log_group.cluster.name
}

output "log_group_retention_days" {
  description = "Retention applied to that log group."
  value       = aws_cloudwatch_log_group.cluster.retention_in_days
}

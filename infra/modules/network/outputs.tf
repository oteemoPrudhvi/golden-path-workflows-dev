output "vpc_id" {
  description = "VPC id."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet ids — internet-facing load balancers."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet ids — EKS nodes and RDS."
  value       = aws_subnet.private[*].id
}

output "availability_zones" {
  description = "AZs in use."
  value       = local.azs
}

output "nat_gateway_ids" {
  description = "NAT gateway ids."
  value       = aws_nat_gateway.this[*].id
}

output "nat_public_ips" {
  description = <<-EOT
    Public addresses of the NAT gateway(s). Everything in a private subnet —
    including pods in either cluster — reaches the internet from these. Anything
    that restricts an internet-facing endpoint by source address must allow them,
    or the clusters lose access to it.
  EOT
  value       = aws_eip.nat[*].public_ip
}

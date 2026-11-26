variable "name_prefix" {
  description = "Prefix for resource names, e.g. omf-dev."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR for the VPC. /16 gives plenty of room for two EKS clusters."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "az_count" {
  description = <<-EOT
    Number of availability zones. Issue #5 requires at least 2 (EKS and ALB
    both need subnets in 2+ AZs). More AZs cost nothing extra here because
    there is only one NAT gateway.
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "az_count must be at least 2 — EKS and the ALB both require two AZs."
  }
}

variable "single_nat_gateway" {
  description = <<-EOT
    One NAT gateway for the whole VPC rather than one per AZ.

    This is a deliberate cost decision for a 1-2 user demo, not an oversight.
    A NAT gateway is roughly $32/month plus data processing, so one-per-AZ
    triples that for availability nobody is relying on here.

    TRADE-OFF: if the AZ holding the NAT gateway fails, private subnets in the
    other AZs lose outbound internet. Acceptable for a demo; set this to false
    before anything resembling production.
  EOT
  type        = bool
  default     = true
}

variable "eks_cluster_names" {
  description = <<-EOT
    Names of the EKS clusters that will use these subnets.

    Needed because subnets must be tagged kubernetes.io/cluster/<name> for
    the AWS Load Balancer Controller to discover them. Getting this wrong is
    a common and confusing failure: the controller silently ignores untagged
    subnets and the ingress never provisions an ALB.
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all resources. Provider default_tags also applies."
  type        = map(string)
  default     = {}
}

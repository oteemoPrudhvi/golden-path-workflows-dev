variable "name_prefix" {
  description = "Prefix for resource names, e.g. omf-dev. Composed by the caller from client and environment."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet ids. AC: RDS must not be reachable from the public internet."
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC id, for the security group."
  type        = string
}

variable "allowed_security_groups" {
  description = <<-EOT
    Security groups permitted to reach Postgres, keyed by a stable label.

    A MAP rather than a list, deliberately. Security group ids come from
    resources created in the same apply, so they are unknown at plan time. A
    list would make the for_each keys unknown and `terraform plan` fails with
    "Invalid for_each argument" before creating anything — which would break
    AC #2. Keying by a label the caller chooses keeps the keys static and
    lets the values resolve at apply.

    Example: { backstage = module.backstage_cluster.cluster_security_group_id }

    Using a security group reference rather than a CIDR also means the rule
    stays correct if the cluster's addressing changes.
  EOT
  type        = map(string)
}

variable "instance_class" {
  description = "RDS instance class. Issue #5 specifies db.t4g.micro/small for a 1-2 user demo."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  description = "Storage in GB. Issue #5 specifies 20."
  type        = number
  default     = 20
}

variable "engine_version" {
  description = <<-EOT
    PostgreSQL major version.

    Pinned rather than left to the provider default so a provider upgrade
    cannot silently propose a major version change on the next plan.
  EOT
  type        = string
  default     = "16"
}

variable "database_name" {
  description = "Initial database name. Backstage creates its own schemas inside this."
  type        = string
  default     = "backstage"
}

variable "master_username" {
  description = "Master username. Not 'admin' or 'postgres' — both are rejected by RDS or heavily targeted."
  type        = string
  default     = "backstage_admin"
}

variable "backup_retention_days" {
  description = "Automated backup retention. Issue #5 requires automated backups."
  type        = number
  default     = 7
}

variable "multi_az" {
  description = "Single-AZ for the demo per issue #5 sizing. Multi-AZ roughly doubles the cost."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = <<-EOT
    Blocks accidental deletion.

    Default false because AC #15 requires `terraform destroy` to cleanly
    remove everything. Turn this on for anything that outlives a demo.
  EOT
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = <<-EOT
    How long CloudWatch keeps these logs.

    RDS exports the PostgreSQL and upgrade logs here. A log group that is never created by Terraform is created
    implicitly with NO retention — it keeps logs forever and the cost grows
    quietly — and is not deleted on destroy. Owning it here fixes retention, tags
    and destroy together. Zero ("never expire") is deliberately not accepted.
  EOT
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch accepts, and not 0 (never expire)."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

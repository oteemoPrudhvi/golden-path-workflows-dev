variable "region" {
  description = "AWS region. Single-region demo."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for all resource names. Issue #5 specifies omf-dev-*."
  type        = string
  default     = "omf-dev"
}

variable "owner" {
  description = "Value for the owner tag. A team or individual accountable for these resources."
  type        = string
  default     = "oteemo-platform"
}

variable "project" {
  description = <<-EOT
    Value for the project tag. Must match envs/omf-dev, or the state bucket is
    the one resource in the account tagged as a different project. It was
    "omf-idx" while everything else said "idx-platform".
  EOT
  type        = string
  default     = "idx-platform"
}

variable "client" {
  description = "Value for the client tag, matching envs/omf-dev."
  type        = string
  default     = "omf"
}

variable "environment" {
  description = "Value for the environment tag. Single environment for this demo."
  type        = string
  default     = "dev"
}

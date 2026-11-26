variable "name_prefix" {
  description = "Prefix for the role and policy names, e.g. omf-dev."
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN of the Argo cluster (IRSA)."
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL of the Argo cluster, without https://."
  type        = string
}

variable "argo_namespace" {
  description = "Namespace the provisioning workflow runs in."
  type        = string
  default     = "argo"
}

variable "service_account" {
  description = "ServiceAccount the provisioning workflow runs as. Only this subject can assume the provisioner role."
  type        = string
  default     = "golden-path-provisioner"
}

variable "resource_prefix" {
  description = <<-EOT
    Everything the provisioner may create or change must be named with this prefix:
    IAM roles (`<prefix>-*`), CodeArtifact domains and repositories (`<prefix>-*`).
    It is what scopes the permissions, so it is validated as a plain lowercase word:
    a wildcard or an empty value would widen them to the whole account.
  EOT
  type        = string
  default     = "gp"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.resource_prefix))
    error_message = "resource_prefix must be 2-10 lowercase letters or digits, starting with a letter. No wildcards, no hyphens."
  }
}

variable "state_key_prefix" {
  description = "Prefix in the Terraform state bucket the provisioner may read and write. Per-package state lives under it."
  type        = string
  default     = "golden-path/packages/"

  validation {
    condition     = endswith(var.state_key_prefix, "/") && !strcontains(var.state_key_prefix, "*")
    error_message = "state_key_prefix must end with / and contain no wildcard."
  }
}

variable "developer_session_names" {
  description = <<-EOT
    Sign-in names (IAM Identity Center usernames, usually the email) of people who may assume
    the developer role, which carries the same permissions as the provisioner. Empty means no
    developer role is created. Exact names only: a wildcard would let anyone with an SSO
    sign-in to this account assume it.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.developer_session_names : !strcontains(n, "*") && !strcontains(n, "?") && length(n) > 3])
    error_message = "Each developer session name must be an exact sign-in name with no wildcard."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

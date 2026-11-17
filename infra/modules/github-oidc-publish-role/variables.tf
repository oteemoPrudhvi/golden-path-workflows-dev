variable "role_name" {
  description = "IAM role name (max 64 characters)."
  type        = string

  validation {
    condition     = length(var.role_name) <= 64 && can(regex("^[A-Za-z0-9+=,.@_-]+$", var.role_name))
    error_message = "role_name must be at most 64 characters and use only IAM-safe characters."
  }
}

variable "github_repository" {
  description = "GitHub repository in org/name form that may assume the role."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in org/name form."
  }
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub Actions IAM OIDC provider."
  type        = string
}

variable "allowed_subjects" {
  description = "OIDC sub claim patterns allowed to assume the role. Pull requests are intentionally not included."
  type        = list(string)

  validation {
    condition     = length(var.allowed_subjects) > 0
    error_message = "At least one allowed subject is required."
  }
}

variable "codeartifact_domain_arn" {
  description = "ARN of the CodeArtifact domain (for the authorization token)."
  type        = string
}

variable "codeartifact_repository_arn" {
  description = "ARN of the CodeArtifact repository the role may read and publish to."
  type        = string
}

variable "codeartifact_package_arn_pattern" {
  description = "Package ARN pattern within that repository."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Optional IAM permissions boundary."
  type        = string
  default     = null
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "tags" {
  description = "Tags applied to the role."
  type        = map(string)
  default     = {}
}

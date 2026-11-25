# ---------------------------------------------------------------------------
# Per-package inputs (passed by the Argo workflow as TF_VAR_*)
# ---------------------------------------------------------------------------
variable "package_name" {
  description = "Python package name. Also the CodeArtifact repository name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.package_name))
    error_message = "package_name must be 2-63 characters: lowercase letters, numbers and hyphens, starting with a letter."
  }
}

variable "repo_url" {
  description = "HTML URL of the GitHub repository, for example https://github.com/Oteemo/my-package."
  type        = string

  validation {
    condition     = can(regex("^https://github.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.repo_url))
    error_message = "repo_url must look like https://github.com/<org>/<repo>."
  }
}

variable "description" {
  description = "Package description."
  type        = string
  default     = ""
}

variable "owner" {
  description = "Owning team or user (applied as a tag)."
  type        = string
  default     = "unknown"
}

variable "publish_enabled" {
  description = "Create the GitHub OIDC publish role. Must be the string true or false."
  type        = string
  default     = "true"

  validation {
    condition     = contains(["true", "false"], lower(var.publish_enabled))
    error_message = "publish_enabled must be true or false."
  }
}

# ---------------------------------------------------------------------------
# Platform settings (set once through the Helm chart values)
# ---------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "codeartifact_domain_name" {
  description = "Existing shared CodeArtifact domain (created once, see docs/aws-prerequisites.md)."
  type        = string
  default     = "golden-path"
}

variable "codeartifact_upstreams" {
  description = "Optional upstream repositories in the domain (for example one proxying PyPI), as a JSON list."
  type        = list(string)
  default     = []
}

variable "role_name_prefix" {
  description = "Prefix of the publish role name. Must be gp-*: the provisioner role only manages gp-* roles."
  type        = string
  default     = "gp-"
}

variable "permissions_boundary_arn" {
  description = "Optional permissions boundary attached to the publish role."
  type        = string
  default     = null
}

variable "extra_tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# GitHub immutable OIDC subject
# ---------------------------------------------------------------------------
# Repositories created recently get this subject on their OIDC token:
#   repo:<owner>@<owner_id>/<name>@<repo_id>:ref:refs/tags/v1.0.0
# instead of repo:<owner>/<name>:ref:... . The Argo workflow passes both ids. With the ids, the role
# trusts ONLY the immutable subject (the name-based one would match a recreated repo of the same
# name). When they are empty, only the name-based subject is trusted (manual runs).
variable "github_repository_id" {
  description = "Numeric GitHub repository id (immutable OIDC subject). Empty to trust only the name-based subject."
  type        = string
  default     = ""

  validation {
    condition     = var.github_repository_id == "" || can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be numeric or empty."
  }
}

variable "github_owner_id" {
  description = "Numeric GitHub id of the repository owner (user or organization). Must be set together with github_repository_id."
  type        = string
  default     = ""

  validation {
    condition     = var.github_owner_id == "" || can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be numeric or empty."
  }

  validation {
    condition     = (var.github_owner_id == "") == (var.github_repository_id == "")
    error_message = "Set github_owner_id and github_repository_id together, or leave both empty."
  }
}

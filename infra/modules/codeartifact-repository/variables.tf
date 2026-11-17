variable "domain" {
  description = "Name of an existing CodeArtifact domain."
  type        = string
}

variable "domain_owner" {
  description = "AWS account ID that owns the domain."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.domain_owner))
    error_message = "domain_owner must be a 12-digit AWS account ID."
  }
}

variable "repository" {
  description = "Repository name."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{1,99}$", var.repository))
    error_message = "repository must be 2-100 characters: letters, numbers, dot, underscore or hyphen, starting with a letter or number."
  }
}

variable "description" {
  description = "Repository description (max 1000 characters)."
  type        = string
  default     = ""

  validation {
    condition     = length(var.description) <= 1000
    error_message = "description must not exceed 1000 characters."
  }
}

variable "upstreams" {
  description = "Names of repositories in the same domain to use as upstreams (for example one that proxies PyPI)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the repository."
  type        = map(string)
  default     = {}
}

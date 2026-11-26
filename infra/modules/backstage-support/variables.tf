variable "name_prefix" {
  description = "Prefix for resource names, e.g. omf-dev."
  type        = string
}

variable "oidc_provider_arn" {
  description = "IRSA OIDC provider ARN from the Backstage EKS cluster."
  type        = string
}

variable "oidc_provider_url" {
  description = "IRSA OIDC issuer URL without the https:// prefix."
  type        = string
}

variable "service_account_namespace" {
  description = "Namespace the Backstage pod runs in."
  type        = string
  default     = "backstage"
}

variable "service_account_name" {
  description = "Kubernetes service account the Backstage pod uses."
  type        = string
  default     = "backstage"
}

variable "ecr_untagged_expiry_days" {
  description = "Days before untagged images expire. AC requires an ECR lifecycle policy."
  type        = number
  default     = 14
}

variable "ecr_tagged_image_count" {
  description = "Number of tagged images to retain."
  type        = number
  default     = 20
}

variable "additional_secret_keys" {
  description = <<-EOT
    Secrets Manager entries to create as empty placeholders.

    Issue #5 lists GITHUB_TOKEN, the Okta client secret and a backend secret.
    Okta sign-in and the org sync need four values in all: client id, client
    secret, domain and an API token. `argo-token` is the credential Backstage
    presents to Argo Workflows (issue #50).
    Terraform creates the containers; the values are set out of band so they
    never enter code, state or a plan file.
  EOT
  type        = list(string)
  default = [
    "github-token",
    "okta-client-id",
    "okta-client-secret",
    "okta-domain",
    "okta-api-token",
    "argo-token",
    "backend-secret",
  ]
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "external_secrets_namespace" {
  description = "Namespace External Secrets Operator runs in."
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_service_account" {
  description = "External Secrets Operator service account name."
  type        = string
  default     = "external-secrets"
}

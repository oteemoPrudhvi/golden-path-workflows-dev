variable "name_prefix" {
  description = "Prefix for resource names, e.g. omf-dev."
  type        = string
}

variable "oidc_provider_arn" {
  description = "IRSA OIDC provider ARN from the Argo EKS cluster."
  type        = string
}

variable "oidc_provider_url" {
  description = "IRSA OIDC issuer URL without the https:// prefix."
  type        = string
}

variable "argo_namespace" {
  description = "Namespace Argo Workflows runs in."
  type        = string
  default     = "argo"
}

variable "workflow_service_accounts" {
  description = <<-EOT
    Service accounts in the Argo namespace that may write artifacts.

    Both are needed: the controller writes archived logs, and the workflow
    pods themselves write step artifacts. Granting only one produces a
    workflow that succeeds but stores nothing, which is a confusing failure
    given AC #9 checks for the artifact.
  EOT
  type        = list(string)
  # Verified by rendering the chart rather than guessed. helm template of
  # argo-workflows 0.45.19 creates exactly two service accounts:
  # argo-workflows-workflow-controller and argo-workflows-server. Workflow
  # pods run as whatever the workflow specifies; the workloads module creates
  # "argo-workflow" explicitly and annotates it.
  #
  # The previous value included "argo-workflows-controller", which the chart
  # never creates — found in review.
  default = ["argo-workflows-workflow-controller", "argo-workflow"]
}

variable "artifact_expiry_days" {
  description = "Days before workflow artifacts expire. Demo artifacts have no long-term value."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

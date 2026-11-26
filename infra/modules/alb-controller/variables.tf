variable "cluster_name" {
  description = "Cluster this controller serves. Used in the role name so two clusters do not collide."
  type        = string
}

variable "oidc_provider_arn" {
  description = "IRSA OIDC provider ARN for the cluster."
  type        = string
}

variable "oidc_provider_url" {
  description = "IRSA OIDC issuer URL without the https:// prefix."
  type        = string
}

variable "namespace" {
  description = "Namespace the controller runs in."
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Controller service account name. Must match the Helm release."
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "name_prefix" {
  description = "Prefix for resource names, e.g. omf-dev."
  type        = string
}

variable "domain_name" {
  description = <<-EOT
    Route 53 hosted zone domain, e.g. omf-idx-demo.click.

    THIS VARIABLE SELECTS THE MODE.

    Set    -> Option A. DNS-validated ACM certificate, trusted by browsers,
              auto-renewing, stable hostnames.
    Empty  -> Option B. Self-signed certificate imported into ACM, attached
              to the ALB. Users get a one-time browser warning.

    Option A is preferred. A domain registered in Route 53 costs a few
    dollars a year and removes an entire class of failure — see the comments
    on Option B in main.tf.
  EOT
  type        = string
  default     = ""
}

variable "create_hosted_zone" {
  description = <<-EOT
    Create the Route 53 hosted zone, or use one that already exists.

    False is the common case: registering a domain through Route 53 creates
    the zone automatically, so Terraform should look it up rather than make
    a second one. Two zones for the same domain is a confusing failure —
    records go in one, nameservers point at the other.
  EOT
  type        = bool
  default     = false
}

variable "backstage_subdomain" {
  description = "Subdomain for Backstage. Issue #5 specifies omf-backstage."
  type        = string
  default     = "omf-backstage"
}

variable "argo_subdomain" {
  description = "Subdomain for the Argo Workflows UI. Issue #5 specifies omf-argo."
  type        = string
  default     = "omf-argo"
}

variable "self_signed_validity_days" {
  description = "Validity for the Option B self-signed certificate."
  type        = number
  default     = 365
}

variable "oidc_provider_arn" {
  description = "Backstage cluster IRSA OIDC provider ARN, for the ExternalDNS role."
  type        = string
  default     = null
}

variable "oidc_provider_url" {
  description = "Backstage cluster IRSA OIDC issuer URL without https://."
  type        = string
  default     = null
}

variable "external_dns_namespace" {
  description = "Namespace ExternalDNS runs in."
  type        = string
  default     = "kube-system"
}

variable "external_dns_service_account" {
  description = "ExternalDNS service account name."
  type        = string
  default     = "external-dns"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "argo_inbound_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the Argo Workflows UI.

    The Argo server runs in `server` auth mode for this demo, which means no
    login. An unrestricted internet-facing ALB would let anyone who learns the
    hostname submit workflows to the cluster. Raised in review.

    Empty means unrestricted — acceptable only if the UI is not exposed at all.
    Set this to the office or VPN range before applying.
  EOT
  type        = list(string)
  default     = []
}

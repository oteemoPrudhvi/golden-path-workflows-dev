variable "region" {
  description = "AWS region. Must match the infrastructure state."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket" {
  description = "S3 bucket holding the infrastructure state. Contains the account id, so passed in rather than hardcoded."
  type        = string
}

variable "infra_state_key" {
  description = "Key of the infrastructure state within the bucket."
  type        = string
  default     = "envs/omf-dev/terraform.tfstate"
}

# --- Chart versions ----------------------------------------------------------
# All pinned. An unpinned chart means the next apply can install a version
# nobody tested, which is the kind of drift that only shows up in a demo.
variable "argo_workflows_chart_version" {
  description = "argo-workflows Helm chart version. Rendered and verified at this version."
  type        = string
  default     = "0.45.19"
}

variable "external_secrets_chart_version" {
  description = "external-secrets Helm chart version."
  type        = string
  default     = "0.19.2"
}

variable "alb_controller_chart_version" {
  description = "aws-load-balancer-controller chart version. Must match the IAM policy in modules/alb-controller."
  type        = string
  default     = "1.13.0"
}

variable "external_dns_chart_version" {
  description = "external-dns chart version. Only installed under Option A."
  type        = string
  default     = "1.15.2"
}

variable "argo_workflow_parallelism" {
  description = <<-EOT
    Maximum workflows running at once across the controller.

    Bounded deliberately. The Argo node group scales to 4 nodes; an unbounded
    controller will schedule more workflows than the cluster can run and they
    queue as Pending, which looks like a hang rather than a limit.
  EOT
  type        = number
  default     = 10
}

variable "create_ingresses" {
  description = <<-EOT
    Create the Backstage and Argo Ingress resources.

    These are what cause the load balancer controller to provision ALBs, so
    ACs #6, #7 and #8 depend on them. Set false only if you want the
    controllers installed without exposing anything yet.

    The Backstage ingress points at a Service that the application deployment
    creates (issue #4). Until that exists the ALB provisions but returns 503,
    which is expected rather than a fault.
  EOT
  type        = bool
  default     = true
}

variable "create_backstage_ingress" {
  description = <<-EOT
    Create the Backstage Ingress (and therefore its ALB).

    On by default. The Ingress targets a `backstage` Service that the
    application deployment (issue #4) creates. That Service need not exist
    first: a probe on 29 Oct 2026 showed the load balancer controller builds the
    ALB and assigns a hostname within ~10s for an Ingress whose backend Service
    is missing (event "SuccessfullyReconciled"). The ALB answers 503 until the
    Service has ready pods.

    This matters for issue #2: Okta needs the final HTTPS hostname for its
    redirect URI, so the ALB has to exist BEFORE Backstage is deployed.

    This was previously off by default, on an assumption that the controller
    would refuse. The assumption was wrong. Set false only to install the
    controllers without exposing Backstage.
  EOT
  type        = bool
  default     = true
}

variable "backstage_service_name" {
  description = "Service the Backstage ingress targets. Created by the application deployment."
  type        = string
  default     = "backstage"
}

variable "backstage_service_port" {
  description = "Port the Backstage service listens on."
  type        = number
  default     = 7007
}

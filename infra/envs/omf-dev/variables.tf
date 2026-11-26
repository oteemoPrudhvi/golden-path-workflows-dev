# =============================================================================
# Inputs for one deployment.
#
# Everything client-specific lives here, not in the modules. Standing this up
# for another client should be a new envs/<client>-<env>/ directory with a
# different terraform.tfvars — no module changes.
# =============================================================================

variable "client" {
  description = <<-EOT
    Short client identifier, lowercase. Forms the first part of every
    resource name.

    This is the variable that makes the stack reusable. 'omf' here,
    something else for the next client.
  EOT
  type        = string
  default     = "omf"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.client))
    error_message = "client must be lowercase alphanumeric with hyphens, 2-20 characters, starting with a letter."
  }
}

variable "environment" {
  description = "Environment name. Issue #5 scopes this to a single 'dev' environment."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.environment))
    error_message = "environment must be lowercase alphanumeric with hyphens, 2-16 characters."
  }
}

variable "region" {
  description = "AWS region. Issue #5 specifies us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "allowed_account_id" {
  description = <<-EOT
    AWS account this configuration is permitted to touch.

    Terraform refuses to plan or apply against any other account. The real
    hazard when running as an administrator is not insufficient permission,
    it is a stale AWS_PROFILE pointing somewhere else — this turns that into
    a loud failure instead of a surprising one.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.allowed_account_id))
    error_message = "allowed_account_id must be a 12-digit AWS account id."
  }
}

variable "owner" {
  description = "Value for the owner tag. A team or individual accountable for these resources."
  type        = string
  default     = "oteemo-platform"
}

variable "project" {
  description = "Value for the project tag."
  type        = string
  default     = "idx-platform"
}

# --- Networking --------------------------------------------------------------
variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Availability zones. Minimum 2 for EKS and the ALB."
  type        = number
  default     = 2
}

# --- Cluster sizing ----------------------------------------------------------
variable "kubernetes_version" {
  description = <<-EOT
    Kubernetes version for both clusters.

    MUST be a version in EKS STANDARD support. Extended support is billed at
    roughly six times the standard control plane rate — about $0.60 per
    cluster-hour against $0.10 — which for two clusters is the difference
    between ~$146 and ~$870 a month.

    This defaulted to 1.31 until review caught it; 1.31 left standard support
    in 2025. Check the current list before changing:
    https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-standard.html
  EOT
  type        = string
  default     = "1.35"

  validation {
    # Blunt but effective: refuse versions known to be out of standard
    # support. Cheaper than discovering it on the bill.
    condition     = !contains(["1.28", "1.29", "1.30", "1.31", "1.32", "1.33"], var.kubernetes_version)
    error_message = "That Kubernetes version is in EKS extended support, billed at ~6x the standard control plane rate. Use a version in standard support."
  }
}

variable "backstage_node_instance_types" {
  description = "Backstage node types. Issue #5 specifies t3.large."
  type        = list(string)
  default     = ["t3.large"]
}

variable "backstage_node_desired" {
  description = "Backstage desired node count."
  type        = number
  default     = 2
}

variable "argo_node_instance_types" {
  description = "Argo Workflows node types. Issue #5 specifies t3.medium."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "argo_node_desired" {
  description = "Argo desired node count."
  type        = number
  default     = 1
}

variable "argo_node_max" {
  description = "Argo maximum node count. Higher than desired so workflow bursts can scale out."
  type        = number
  default     = 4
}

variable "cluster_public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the Kubernetes API endpoints.

    Open by default because a demo needs kubectl from laptops and CI without
    a bastion. Narrow this for anything longer-lived.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- Database ----------------------------------------------------------------
variable "db_instance_class" {
  description = "RDS instance class. Issue #5 specifies db.t4g.micro/small."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage_gb" {
  description = "RDS storage. Issue #5 specifies 20 GB."
  type        = number
  default     = 20
}

# --- Ingress / TLS -----------------------------------------------------------
variable "domain_name" {
  description = <<-EOT
    Route 53 domain for Option A, or empty for Option B.

    Set    -> trusted DNS-validated certificate, stable hostnames.
    Empty  -> self-signed certificate on the ALB hostname, browser warning.

    Both are implemented; this is the only change needed to switch.
  EOT
  type        = string
  default     = ""
}

variable "create_hosted_zone" {
  description = "Create the Route 53 zone, or look up an existing one. False if the domain was registered through Route 53."
  type        = bool
  default     = false
}

# --- CI ----------------------------------------------------------------------
variable "github_org" {
  description = "GitHub organisation for the OIDC trust policy."
  type        = string
  default     = "Oteemo"
}

variable "github_repo" {
  description = "Repository allowed to assume the CI role."
  type        = string
  default     = "backstage-app"
}

variable "github_allowed_refs" {
  description = "Branches permitted to assume the CI role. Feature branches deliberately excluded."
  type        = list(string)
  default     = ["refs/heads/dev", "refs/heads/master"]
}

variable "github_create_oidc_provider" {
  description = <<-EOT
    Create the GitHub OIDC provider in this account.

    An account can hold only one provider per issuer URL. Leave true for a
    fresh account. Set false when one already exists — as it does in the
    Oteemo sandbox, created 24 April by another stack — and supply
    github_existing_oidc_provider_arn. Found by the first real apply, which
    failed with EntityAlreadyExists; no amount of CI could have caught it.
  EOT
  type        = bool
  default     = true
}

variable "github_existing_oidc_provider_arn" {
  description = "ARN of the existing GitHub OIDC provider. Required when github_create_oidc_provider is false."
  type        = string
  default     = null

  validation {
    condition     = var.github_existing_oidc_provider_arn == null || can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.github_existing_oidc_provider_arn))
    error_message = "Must be the ARN of the token.actions.githubusercontent.com provider, e.g. arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com."
  }
}

variable "log_retention_days" {
  description = "Retention for the EKS and RDS CloudWatch log groups Terraform owns. 30 is plenty for a demo; unbounded was the previous, accidental, behaviour."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch accepts, and not 0 (never expire) — unbounded retention is how these groups leaked before."
  }
}

variable "adopt_existing_log_groups" {
  description = <<-EOT
    Import the log groups that already exist into state instead of creating them.

    EKS and RDS create their log groups implicitly the first time logging is on, so
    an environment applied BEFORE Terraform owned them already has them, and
    creating them again fails with "already exists". Set true ONCE for such an
    environment (this sandbox), apply, then it can stay true or go back to false.

    Leave false for a fresh account: there the groups do not exist yet, and an
    import of something that does not exist is an error.
  EOT
  type        = bool
  default     = false
}

variable "github_subject_prefix" {
  description = <<-EOT
    The front of the OIDC subject GitHub presents for the repository.

    This repository issues IMMUTABLE subject claims, which embed the numeric owner
    and repository ids. A role trusting the classic `repo:Oteemo/backstage-app`
    form was merged and could not be assumed by any workflow. The ids are public
    (they are in the GitHub API), so they live here as a default rather than in a
    gitignored tfvars where a clean checkout would silently regress.

    For another repository, read yours:
      gh api repos/<org>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix
    Set null to fall back to the classic form if immutable subjects are off.
  EOT
  type        = string
  default     = "repo:Oteemo@19363462/backstage-app@1435925066"
}

variable "github_allowed_environments" {
  description = <<-EOT
    GitHub Environments permitted to assume the CI role.

    A job that declares `environment: dev` presents the OIDC subject
    `environment:dev`, NOT `ref:refs/heads/dev` — so a role that trusts only
    branches rejects it. Issue #4 specifies a GitHub Environment named `dev`
    for its deploy job, which would have failed at AssumeRoleWithWebIdentity.
  EOT
  type        = list(string)
  default     = ["dev"]
}

variable "argo_inbound_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the Argo Workflows UI.

    The Argo server runs without login in this demo, so leaving this empty
    means anyone who learns the ALB hostname can submit workflows. Set it to
    an office or VPN range before applying.

    The NAT gateway address is added automatically when this is non-empty:
    Backstage reaches Argo over the public ALB, from inside the VPC, and exits
    through the NAT — so without it the restriction would lock Backstage out
    of Argo as well (issue #1).
  EOT
  type        = list(string)
  default     = []
}

variable "backstage_namespace" {
  description = "Namespace Backstage runs in. CI's access entry is scoped to it."
  type        = string
  default     = "backstage"
}

variable "argo_namespace" {
  description = "Namespace Argo Workflows runs in. CI's access entry is scoped to it."
  type        = string
  default     = "argo"
}

variable "golden_path_developers" {
  description = <<-EOT
    IAM Identity Center sign-in names (usually the email) of people who may assume the
    golden-path developer role: scoped access to create CodeArtifact repositories and
    publish-only roles named gp-*, and nothing else. Exact names, no wildcards. Empty means
    no developer role exists. Set in terraform.tfvars, which is not committed.
  EOT
  type        = list(string)
  default     = []
}

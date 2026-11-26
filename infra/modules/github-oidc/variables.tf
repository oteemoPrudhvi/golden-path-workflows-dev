variable "name_prefix" {
  description = "Prefix for resource names, e.g. omf-dev."
  type        = string
}

variable "github_org" {
  description = "GitHub organisation that owns the repository, e.g. Oteemo."
  type        = string
}

variable "github_repo" {
  description = "Repository name allowed to assume the role, e.g. backstage-app."
  type        = string
}

variable "subject_prefix" {
  description = <<-EOT
    The front of the OIDC `sub` claim GitHub presents for this repository.

    Null means the classic form, `repo:<org>/<repo>`. But GitHub can issue
    IMMUTABLE subject claims that embed the numeric owner and repository ids —
    `repo:<org>@<owner-id>/<repo>@<repo-id>` — and when a repository has that on,
    a role trusting the classic form can never be assumed: every attempt is denied.
    Read the real value rather than guessing:

      gh api repos/<org>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix

    Found by the first real workflow run, which was denied; CloudTrail recorded the
    subject GitHub actually sent.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.subject_prefix == null || (startswith(coalesce(var.subject_prefix, "x"), "repo:") && !strcontains(coalesce(var.subject_prefix, ""), "*"))
    error_message = "subject_prefix must start with \"repo:\" and contain no wildcard — a wildcard would let a fork's pull request assume the role."
  }
}

variable "allowed_refs" {
  description = <<-EOT
    Git refs permitted to assume the role.

    This is the single most important setting in this module. The trust
    policy matches on the OIDC `sub` claim, which looks like:
      repo:<org>/<repo>:ref:refs/heads/<branch>

    A wildcard of `repo:<org>/<repo>:*` would let ANY branch — including one
    opened by a fork's pull request — assume a role that can push images and
    deploy to EKS. Restricting to specific branches is what makes this
    least-privilege in practice rather than on paper.

    Default allows the two long-lived branches only. Feature branches get no
    deploy credentials, which is correct: CI for a feature branch should
    lint, test and build, not deploy.
  EOT
  type        = list(string)
  default     = ["refs/heads/dev", "refs/heads/master"]
}

variable "allowed_environments" {
  description = <<-EOT
    GitHub Environments permitted to assume the role, in addition to branches.

    Environments support required reviewers, so gating a deploy behind one
    adds human approval without Terraform knowing anything about it. Empty
    by default.
  EOT
  type        = list(string)
  default     = []
}

variable "create_oidc_provider" {
  description = <<-EOT
    Create the GitHub OIDC provider in this account.

    An account can only have one provider per issuer URL. Set false if
    another stack already created it, and pass existing_oidc_provider_arn.
  EOT
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of an existing GitHub OIDC provider. Required when create_oidc_provider is false."
  type        = string
  default     = null

  validation {
    condition     = var.existing_oidc_provider_arn == null || can(regex("^arn:aws:iam::", var.existing_oidc_provider_arn))
    error_message = "existing_oidc_provider_arn must be an IAM ARN."
  }
}

variable "ecr_repository_arns" {
  description = "ECR repositories the pipeline may push to. AC #11: ECR push."
  type        = list(string)
  default     = []
}

variable "techdocs_bucket_arns" {
  description = <<-EOT
    S3 buckets the pipeline may publish built TechDocs to. Read, write and delete on
    objects, list on the bucket, and nothing else. Empty means no S3 access.

    These are exact bucket ARNs: a wildcard would let a compromised workflow write
    to every bucket in the account.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.techdocs_bucket_arns : startswith(arn, "arn:aws:s3:::") && !strcontains(arn, "*") && !strcontains(arn, "/")])
    error_message = "Each entry must be a bucket ARN (arn:aws:s3:::<bucket>) with no wildcard and no object path."
  }
}

variable "eks_cluster_arns" {
  description = "EKS clusters the pipeline may describe in order to deploy. AC #11: EKS deploy."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

data "aws_caller_identity" "current" {}

# GitHub Actions OIDC provider. Created once per account (docs/aws-prerequisites.md).
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  publish_enabled = lower(var.publish_enabled) == "true"

  # https://github.com/Oteemo/my-package(.git) -> Oteemo/my-package
  github_repository = trimsuffix(replace(var.repo_url, "https://github.com/", ""), ".git")

  # Applied to every resource through the provider's default_tags (see versions.tf).
  tags = merge(
    {
      ManagedBy  = "argo-python-package-provisioning"
      Package    = var.package_name
      Owner      = var.owner
      Repository = local.github_repository
    },
    var.extra_tags,
  )

  domain_arn = "arn:aws:codeartifact:${var.aws_region}:${local.account_id}:domain/${var.codeartifact_domain_name}"

  # Only version tags and the default branch may publish. Pull requests are not listed,
  # so code from a pull request can never assume the publish role.
  #
  # GitHub puts one of two subject formats on the token: the name-based
  # repo:<owner>/<name>:... and, for newer repositories, the immutable
  # repo:<owner>@<owner_id>/<name>@<repo_id>:... .
  #
  # When the ids are known, trust ONLY the immutable form. The name-based form matches any
  # repository that later gets the same name, so if this role outlived a deleted repo, whoever
  # recreated the name and pushed a v* tag (or the default branch) could publish. The ids
  # change when a repository or account is recreated, so the immutable form cannot be
  # reused that way. The name-based form is the fallback only when no ids are given
  # (manual runs); the workflow always passes them.
  github_owner = split("/", local.github_repository)[0]
  github_name  = split("/", local.github_repository)[1]

  subject_prefixes = var.github_repository_id == "" ? [
    "repo:${local.github_repository}",
    ] : [
    "repo:${local.github_owner}@${var.github_owner_id}/${local.github_name}@${var.github_repository_id}",
  ]

  allowed_subjects = flatten([
    for prefix in local.subject_prefixes : [
      "${prefix}:ref:refs/tags/*",
      "${prefix}:ref:refs/heads/${var.default_branch}",
    ]
  ])
}

module "repository" {
  source = "./modules/codeartifact-repository"

  domain       = var.codeartifact_domain_name
  domain_owner = local.account_id
  repository   = var.package_name
  description  = substr(var.description, 0, 1000)
  upstreams    = var.codeartifact_upstreams
}

module "publish_role" {
  source = "./modules/github-oidc-publish-role"
  count  = local.publish_enabled ? 1 : 0

  role_name                        = "${var.role_name_prefix}${var.package_name}"
  github_repository                = local.github_repository
  oidc_provider_arn                = data.aws_iam_openid_connect_provider.github.arn
  allowed_subjects                 = local.allowed_subjects
  codeartifact_domain_arn          = local.domain_arn
  codeartifact_repository_arn      = module.repository.arn
  codeartifact_package_arn_pattern = "arn:aws:codeartifact:${var.aws_region}:${local.account_id}:package/${var.codeartifact_domain_name}/${var.package_name}/*"
  permissions_boundary_arn         = var.permissions_boundary_arn
}

# =============================================================================
# SCOPED AWS ACCESS FOR THE GOLDEN-PATH PROVISIONING WORKFLOW (issue #57)
# =============================================================================
# The Argo workflow that creates a new Python package runs Terraform to create a
# CodeArtifact repository and a publish-only IAM role for that package. Creating IAM
# roles is the dangerous part: a role that can create roles can grant itself anything.
# So this module does three things:
#
#   1. Scopes every permission by NAME: only `<prefix>-*` roles, domains and
#      repositories, and only one prefix of the state bucket.
#   2. Forces every role it creates to carry a PERMISSION BOUNDARY that allows
#      publishing to CodeArtifact and nothing else. Even a role the workflow writes a
#      generous policy into can only ever do that. The boundary cannot be removed
#      (explicit deny).
#   3. Allows no managed-policy attachment, no user or key creation, no PassRole.
#
# The same permissions can be given to named people through a developer role, so they
# can test the Terraform without broad account access.
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  # Terraform state bucket from bootstrap: "<name_prefix>-tfstate-<account>".
  state_bucket_arn = "arn:${local.partition}:s3:::${var.name_prefix}-tfstate-${local.account_id}"

  github_oidc_provider_arn = "arn:${local.partition}:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"

  role_arn_pattern       = "arn:${local.partition}:iam::${local.account_id}:role/${var.resource_prefix}-*"
  domain_arn_pattern     = "arn:${local.partition}:codeartifact:${local.region}:${local.account_id}:domain/${var.resource_prefix}-*"
  repository_arn_pattern = "arn:${local.partition}:codeartifact:${local.region}:${local.account_id}:repository/${var.resource_prefix}-*/*"
  package_arn_pattern    = "arn:${local.partition}:codeartifact:${local.region}:${local.account_id}:package/${var.resource_prefix}-*/*/*/*/*"

  # The one subject that may assume the provisioner role through IRSA.
  provisioner_subject = "system:serviceaccount:${var.argo_namespace}:${var.service_account}"

  create_developer_role = length(var.developer_session_names) > 0
}

# --- The boundary every created role must carry ------------------------------
data "aws_iam_policy_document" "boundary" {
  statement {
    sid       = "CodeArtifactAuthToken"
    effect    = "Allow"
    actions   = ["codeartifact:GetAuthorizationToken"]
    resources = [local.domain_arn_pattern]
  }

  statement {
    sid       = "CodeArtifactServiceBearerToken"
    effect    = "Allow"
    actions   = ["sts:GetServiceBearerToken"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "sts:AWSServiceName"
      values   = ["codeartifact.amazonaws.com"]
    }
  }

  statement {
    sid       = "CodeArtifactEndpoint"
    effect    = "Allow"
    actions   = ["codeartifact:GetRepositoryEndpoint", "codeartifact:ReadFromRepository"]
    resources = [local.repository_arn_pattern]
  }

  statement {
    sid       = "CodeArtifactPublish"
    effect    = "Allow"
    actions   = ["codeartifact:PublishPackageVersion", "codeartifact:PutPackageMetadata"]
    resources = [local.package_arn_pattern]
  }
}

resource "aws_iam_policy" "boundary" {
  name        = "${var.name_prefix}-golden-path-boundary"
  description = "Permission boundary for roles created by the golden-path provisioner: CodeArtifact publish only."
  policy      = data.aws_iam_policy_document.boundary.json
  tags        = merge(var.tags, { Name = "${var.name_prefix}-golden-path-boundary" })
}

# --- What the provisioner (and the developer role) may do --------------------
data "aws_iam_policy_document" "provision" {
  # CodeArtifact: manage only domains and repositories with our prefix.
  statement {
    sid    = "CodeArtifactManageOwnDomainsAndRepositories"
    effect = "Allow"
    actions = [
      "codeartifact:CreateDomain",
      "codeartifact:DeleteDomain",
      "codeartifact:DescribeDomain",
      "codeartifact:GetDomainPermissionsPolicy",
      "codeartifact:PutDomainPermissionsPolicy",
      "codeartifact:DeleteDomainPermissionsPolicy",
      "codeartifact:CreateRepository",
      "codeartifact:DeleteRepository",
      "codeartifact:DescribeRepository",
      "codeartifact:UpdateRepository",
      "codeartifact:GetRepositoryPermissionsPolicy",
      "codeartifact:PutRepositoryPermissionsPolicy",
      "codeartifact:DeleteRepositoryPermissionsPolicy",
      "codeartifact:ListTagsForResource",
      "codeartifact:TagResource",
      "codeartifact:UntagResource",
    ]
    resources = [local.domain_arn_pattern, local.repository_arn_pattern]
  }

  # Listing has no resource to scope to. Read-only metadata.
  statement {
    sid       = "CodeArtifactList"
    effect    = "Allow"
    actions   = ["codeartifact:ListDomains", "codeartifact:ListRepositories", "codeartifact:ListRepositoriesInDomain"]
    resources = ["*"]
  }

  # IAM: create roles only with the boundary attached, only with our prefix.
  statement {
    sid       = "CreateOwnRolesOnlyWithBoundary"
    effect    = "Allow"
    actions   = ["iam:CreateRole"]
    resources = [local.role_arn_pattern]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.boundary.arn]
    }
  }

  statement {
    sid    = "ManageOwnRoles"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [local.role_arn_pattern]
  }

  # Reuse the existing GitHub OIDC provider; never create or change one.
  statement {
    sid       = "ReadGithubOidcProvider"
    effect    = "Allow"
    actions   = ["iam:GetOpenIDConnectProvider"]
    resources = [local.github_oidc_provider_arn]
  }

  statement {
    sid       = "ListOidcProviders"
    effect    = "Allow"
    actions   = ["iam:ListOpenIDConnectProviders"]
    resources = ["*"]
  }

  # The boundary must stay on, and nothing may be attached by reference or passed on.
  statement {
    sid    = "BoundaryCannotBeRemovedAndNoManagedPolicies"
    effect = "Deny"
    actions = [
      "iam:DeleteRolePermissionsBoundary",
      "iam:PutRolePermissionsBoundary",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PassRole",
    ]
    resources = ["*"]
  }

  # Terraform state for packages, and nothing else in the bucket.
  statement {
    sid       = "StateObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/${var.state_key_prefix}*"]
  }

  statement {
    sid       = "StateList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.state_key_prefix}*"]
    }
  }
}

# --- Provisioner role: used by the workflow through IRSA ---------------------
data "aws_iam_policy_document" "provisioner_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    # One exact subject, not a pattern.
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = [local.provisioner_subject]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "provisioner" {
  name                 = "${var.name_prefix}-golden-path-provisioner"
  description          = "Run by the golden-path provisioning workflow (Argo cluster, IRSA). Scoped by name and a permission boundary."
  assume_role_policy   = data.aws_iam_policy_document.provisioner_assume.json
  max_session_duration = 3600
  tags                 = merge(var.tags, { Name = "${var.name_prefix}-golden-path-provisioner" })
}

resource "aws_iam_role_policy" "provisioner" {
  name   = "${var.name_prefix}-golden-path-provision"
  role   = aws_iam_role.provisioner.id
  policy = data.aws_iam_policy_document.provision.json
}

# --- Developer role: the same permissions, for named people ------------------
# Trust is the account's SSO roles, narrowed to exact sign-in names. A session name in
# IAM Identity Center is the username, and appears in aws:userid as "<id>:<username>".
data "aws_iam_policy_document" "developer_assume" {
  count = local.create_developer_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:${local.partition}:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_*"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:userid"
      values   = [for n in var.developer_session_names : "*:${n}"]
    }
  }
}

resource "aws_iam_role" "developer" {
  count = local.create_developer_role ? 1 : 0

  name                 = "${var.name_prefix}-golden-path-developer"
  description          = "Assumed by named people to test the golden-path Terraform. Same scope as the provisioner."
  assume_role_policy   = data.aws_iam_policy_document.developer_assume[0].json
  max_session_duration = 3600
  tags                 = merge(var.tags, { Name = "${var.name_prefix}-golden-path-developer" })
}

resource "aws_iam_role_policy" "developer" {
  count = local.create_developer_role ? 1 : 0

  name   = "${var.name_prefix}-golden-path-provision"
  role   = aws_iam_role.developer[0].id
  policy = data.aws_iam_policy_document.provision.json
}

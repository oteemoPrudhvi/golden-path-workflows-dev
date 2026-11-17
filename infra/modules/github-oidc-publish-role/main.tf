data "aws_iam_policy_document" "assume" {
  statement {
    sid     = "GitHubOidc"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.allowed_subjects
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = "GitHub Actions publish role for ${var.github_repository}"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

data "aws_iam_policy_document" "publish" {
  statement {
    sid       = "AuthorizationToken"
    actions   = ["codeartifact:GetAuthorizationToken"]
    resources = [var.codeartifact_domain_arn]
  }

  statement {
    sid       = "ServiceBearerToken"
    actions   = ["sts:GetServiceBearerToken"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "sts:AWSServiceName"
      values   = ["codeartifact.amazonaws.com"]
    }
  }

  statement {
    sid = "RepositoryAccess"
    actions = [
      "codeartifact:DescribeRepository",
      "codeartifact:GetRepositoryEndpoint",
      "codeartifact:ReadFromRepository",
    ]
    resources = [var.codeartifact_repository_arn]
  }

  statement {
    sid = "PublishPackages"
    actions = [
      "codeartifact:PublishPackageVersion",
      "codeartifact:PutPackageMetadata",
    ]
    resources = [var.codeartifact_package_arn_pattern]
  }
}

resource "aws_iam_role_policy" "publish" {
  name   = "codeartifact-publish"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.publish.json
}

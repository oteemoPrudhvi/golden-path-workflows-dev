# Plan-level tests. No AWS calls, no credentials.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  role_name                        = "gp-my-package"
  github_repository                = "Oteemo/my-package"
  oidc_provider_arn                = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  allowed_subjects                 = ["repo:Oteemo/my-package:ref:refs/tags/v*"]
  codeartifact_domain_arn          = "arn:aws:codeartifact:us-east-1:123456789012:domain/gp-python-package"
  codeartifact_repository_arn      = "arn:aws:codeartifact:us-east-1:123456789012:repository/gp-python-package/my-package"
  codeartifact_package_arn_pattern = "arn:aws:codeartifact:us-east-1:123456789012:package/gp-python-package/my-package/*"
}

run "role_is_named_from_input" {
  command = plan

  assert {
    condition     = aws_iam_role.this.name == "gp-my-package"
    error_message = "Role name must come from role_name."
  }
}

run "session_duration_defaults_to_an_hour" {
  command = plan

  assert {
    condition     = aws_iam_role.this.max_session_duration == 3600
    error_message = "CI credentials should last an hour by default."
  }
}

run "permissions_boundary_is_applied_when_given" {
  command = plan

  variables {
    permissions_boundary_arn = "arn:aws:iam::123456789012:policy/omf-dev-golden-path-boundary"
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == "arn:aws:iam::123456789012:policy/omf-dev-golden-path-boundary"
    error_message = "The permissions boundary must be attached to the role."
  }
}

run "empty_subjects_are_rejected" {
  command = plan

  variables {
    allowed_subjects = []
  }

  expect_failures = [var.allowed_subjects]
}

run "a_too_long_role_name_is_rejected" {
  command = plan

  variables {
    role_name = "gp-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }

  expect_failures = [var.role_name]
}

run "a_malformed_repository_is_rejected" {
  command = plan

  variables {
    github_repository = "not-org-slash-name"
  }

  expect_failures = [var.github_repository]
}

run "session_duration_over_twelve_hours_is_rejected" {
  command = plan

  variables {
    max_session_duration = 50000
  }

  expect_failures = [var.max_session_duration]
}

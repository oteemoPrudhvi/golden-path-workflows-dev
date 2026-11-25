# Plan-level tests for the per-package root module. No AWS calls, no credentials.
#
# Guarded here: the publish role is trusted only from version tags and the
# default branch (never pull requests), names derive from the package, and
# bad input is rejected before anything is planned.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  package_name = "my-package"
  repo_url     = "https://github.com/Oteemo/my-package"
}

run "repository_is_named_after_the_package" {
  command = plan

  assert {
    condition     = module.repository.repository == "my-package"
    error_message = "The CodeArtifact repository must be named after the package."
  }
}

run "github_repository_is_derived_from_the_url" {
  command = plan

  assert {
    condition     = local.github_repository == "Oteemo/my-package"
    error_message = "org/name must be derived from repo_url."
  }
}

run "pull_requests_cannot_assume_the_publish_role" {
  command = plan

  assert {
    condition     = !anytrue([for s in local.allowed_subjects : strcontains(s, "pull_request")])
    error_message = "Pull request subjects must never be trusted."
  }

  assert {
    condition = toset(local.allowed_subjects) == toset([
      "repo:Oteemo/my-package:ref:refs/tags/v*",
    ])
    error_message = "Only version tags may publish."
  }
}

run "role_name_uses_the_gp_prefix" {
  command = plan

  assert {
    condition     = module.publish_role[0].role_name == "gp-my-package"
    error_message = "The provisioner role only manages gp-* roles."
  }
}

run "publishing_can_be_disabled" {
  command = plan

  variables {
    publish_enabled = "false"
  }

  assert {
    condition     = length(module.publish_role) == 0
    error_message = "No role should be planned when publishing is disabled."
  }
}

run "an_invalid_package_name_is_rejected" {
  command = plan

  variables {
    package_name = "My_Package"
  }

  expect_failures = [var.package_name]
}

run "a_non_github_url_is_rejected" {
  command = plan

  variables {
    repo_url = "https://example.com/Oteemo/my-package"
  }

  expect_failures = [var.repo_url]
}

run "publish_enabled_must_be_true_or_false" {
  command = plan

  variables {
    publish_enabled = "yes"
  }

  expect_failures = [var.publish_enabled]
}

# GitHub puts the immutable subject repo:<owner>@<owner_id>/<name>@<repo_id> on the OIDC
# token of newer repositories. Without these ids in the trust policy AWS answers
# "Not authorized to perform sts:AssumeRoleWithWebIdentity".
run "immutable_subject_is_trusted_when_ids_are_given" {
  command = plan

  variables {
    github_owner_id      = "111111111"
    github_repository_id = "222222222"
  }

  assert {
    condition     = contains(local.allowed_subjects, "repo:Oteemo@111111111/my-package@222222222:ref:refs/tags/v*")
    error_message = "The immutable tag subject must be trusted."
  }

  assert {
    condition     = !anytrue([for s in local.allowed_subjects : strcontains(s, "refs/heads/")])
    error_message = "No branch may be trusted: only version tags publish."
  }

  # The name-based subject matches any repo recreated with the same name: it must be gone.
  assert {
    condition     = !anytrue([for s in local.allowed_subjects : startswith(s, "repo:Oteemo/my-package:")])
    error_message = "With the ids known, the name-based subject must not be trusted."
  }

  assert {
    condition     = length(local.allowed_subjects) == 1
    error_message = "Only the immutable version-tag subject is expected."
  }

  assert {
    condition     = alltrue([for s in local.allowed_subjects : !strcontains(s, "pull_request")])
    error_message = "Pull requests must never be trusted."
  }
}

run "only_the_name_based_subject_without_ids" {
  command = plan

  assert {
    condition     = length(local.allowed_subjects) == 1
    error_message = "Without ids only the name-based version-tag subject is expected."
  }
}

run "ids_must_be_set_together" {
  command = plan

  variables {
    github_repository_id = "222222222"
  }

  expect_failures = [var.github_owner_id]
}

run "ids_must_be_numeric" {
  command = plan

  variables {
    github_owner_id      = "abc"
    github_repository_id = "222222222"
  }

  expect_failures = [var.github_owner_id]
}

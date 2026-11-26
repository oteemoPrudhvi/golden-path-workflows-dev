# Plan-level tests. No AWS calls, no credentials.
#
# These guard the trust policy, which is the part of this module where a
# mistake is expensive rather than merely annoying.

mock_provider "aws" {
  # aws_iam_role_policy validates its policy argument as JSON at plan time.
  # Without a valid default the mocked data source returns a placeholder
  # string and the plan fails before any assertion runs.
  #
  # This does not weaken the tests below: they assert on local.allowed_subjects,
  # which is computed in HCL from the input variables, not on the rendered
  # policy document.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix = "omf-dev"
  github_org  = "Oteemo"
  github_repo = "backstage-app"
}

run "trust_is_scoped_to_named_branches" {
  command = plan

  assert {
    condition = contains(
      local.allowed_subjects,
      "repo:Oteemo/backstage-app:ref:refs/heads/dev"
    )
    error_message = "The dev branch should be able to assume the role."
  }

  # The failure this prevents: a wildcard subject lets a fork's pull request
  # assume a role that can push images and deploy.
  assert {
    condition     = !contains(local.allowed_subjects, "repo:Oteemo/backstage-app:*")
    error_message = "Trust policy must not contain a wildcard subject."
  }

  assert {
    condition     = alltrue([for s in local.allowed_subjects : !strcontains(s, "*")])
    error_message = "No subject claim may contain a wildcard."
  }
}

run "feature_branches_are_not_trusted_by_default" {
  command = plan

  assert {
    condition = !contains(
      local.allowed_subjects,
      "repo:Oteemo/backstage-app:ref:refs/heads/infra/5-eks-clusters"
    )
    error_message = "Feature branches must not get deploy credentials by default."
  }
}

run "environments_can_be_added" {
  command = plan

  variables {
    allowed_environments = ["production"]
  }

  assert {
    condition = contains(
      local.allowed_subjects,
      "repo:Oteemo/backstage-app:environment:production"
    )
    error_message = "GitHub Environments should be addable as trusted subjects."
  }
}

run "session_duration_is_bounded" {
  command = plan

  assert {
    condition     = aws_iam_role.github_actions.max_session_duration <= 3600
    error_message = "CI credentials should last an hour at most."
  }
}

run "adapts_to_a_different_client" {
  command = plan

  # Reusability check: the module must work for another client with no code
  # change, only different inputs.
  variables {
    name_prefix = "acme-dev"
    github_org  = "AcmeCorp"
    github_repo = "platform"
  }

  assert {
    condition     = aws_iam_role.github_actions.name == "acme-dev-github-actions"
    error_message = "Role name should derive from name_prefix, not be hardcoded."
  }

  assert {
    condition = contains(
      local.allowed_subjects,
      "repo:AcmeCorp/platform:ref:refs/heads/dev"
    )
    error_message = "Trust policy should derive from the supplied org and repo."
  }
}

# --- Immutable subject claims ------------------------------------------------
# The first real workflow run was denied: GitHub presented
#   repo:Oteemo@19363462/backstage-app@1435925066:ref:refs/heads/dev
# and the role trusted
#   repo:Oteemo/backstage-app:ref:refs/heads/dev
# The tests above asserted the classic form against the classic form, so every one
# of them passed on a role nothing could assume. These assert the form GitHub
# actually sends, for both kinds of subject.

run "immutable_subject_prefix_is_used_for_branches_and_environments" {
  command = plan

  variables {
    subject_prefix       = "repo:Oteemo@19363462/backstage-app@1435925066"
    allowed_refs         = ["refs/heads/dev"]
    allowed_environments = ["dev"]
  }

  assert {
    condition = toset(local.allowed_subjects) == toset([
      "repo:Oteemo@19363462/backstage-app@1435925066:ref:refs/heads/dev",
      "repo:Oteemo@19363462/backstage-app@1435925066:environment:dev",
    ])
    error_message = "Both subject kinds must carry the immutable prefix, and nothing else may be trusted."
  }

  assert {
    condition     = !anytrue([for s in local.allowed_subjects : startswith(s, "repo:Oteemo/backstage-app:")])
    error_message = "The classic subject form must not be trusted alongside the immutable one: GitHub sends only one, and trusting both widens the policy for no benefit."
  }
}

run "a_wildcard_prefix_is_rejected" {
  command = plan

  variables {
    subject_prefix = "repo:Oteemo/*"
  }

  expect_failures = [var.subject_prefix]
}

run "a_prefix_that_is_not_a_repo_subject_is_rejected" {
  command = plan

  variables {
    subject_prefix = "Oteemo/backstage-app"
  }

  expect_failures = [var.subject_prefix]
}

run "techdocs_publish_access_plans_for_a_named_bucket" {
  command = plan

  variables {
    techdocs_bucket_arns = ["arn:aws:s3:::omf-dev-techdocs-example"]
  }

  assert {
    condition     = aws_iam_role.github_actions.name == "omf-dev-github-actions"
    error_message = "Adding a TechDocs bucket must not change the role."
  }
}

run "a_wildcard_techdocs_bucket_is_rejected" {
  command = plan

  variables {
    techdocs_bucket_arns = ["arn:aws:s3:::*"]
  }

  expect_failures = [var.techdocs_bucket_arns]
}

run "an_object_path_is_not_a_bucket_arn" {
  command = plan

  variables {
    techdocs_bucket_arns = ["arn:aws:s3:::omf-dev-techdocs-example/docs"]
  }

  expect_failures = [var.techdocs_bucket_arns]
}

run "something_that_is_not_an_s3_arn_is_rejected" {
  command = plan

  variables {
    techdocs_bucket_arns = ["omf-dev-techdocs-example"]
  }

  expect_failures = [var.techdocs_bucket_arns]
}

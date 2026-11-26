# Plan-level tests. No AWS calls, no credentials.
#
# These guard the properties that make this module safe to give to a workflow that
# creates IAM roles: the trust is one exact subject, nothing is created for people
# unless they are named, and the values that scope the permissions cannot be widened
# by passing a wildcard.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix       = "omf-dev"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
  oidc_provider_url = "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
}

run "provisioner_trusts_one_exact_service_account" {
  command = plan

  assert {
    condition     = local.provisioner_subject == "system:serviceaccount:argo:golden-path-provisioner"
    error_message = "The provisioner role must trust exactly one ServiceAccount subject."
  }

  assert {
    condition     = !strcontains(local.provisioner_subject, "*")
    error_message = "The trusted subject must not contain a wildcard."
  }
}

run "permissions_are_scoped_by_the_name_prefix" {
  command = plan

  assert {
    condition     = local.role_arn_pattern == "arn:aws:iam::123456789012:role/gp-*"
    error_message = "IAM role permissions must be limited to roles named with the prefix."
  }

  assert {
    condition     = local.domain_arn_pattern == "arn:aws:codeartifact:us-east-1:123456789012:domain/gp-*"
    error_message = "CodeArtifact domain permissions must be limited to the prefix."
  }

  assert {
    condition     = local.state_bucket_arn == "arn:aws:s3:::omf-dev-tfstate-123456789012"
    error_message = "State access must point at the bootstrap state bucket."
  }
}

run "no_developer_role_unless_people_are_named" {
  command = plan

  assert {
    condition     = length(aws_iam_role.developer) == 0
    error_message = "With no developer names there must be no developer role."
  }

  assert {
    condition     = output.developer_role_arn == null
    error_message = "The developer role output must be null when no role exists."
  }
}

run "developer_role_exists_when_a_person_is_named" {
  command = plan

  variables {
    developer_session_names = ["prudhvi@example.com"]
  }

  assert {
    condition     = length(aws_iam_role.developer) == 1
    error_message = "Naming a developer should create the developer role."
  }
}

run "adapts_to_a_different_client" {
  command = plan

  variables {
    name_prefix = "acme-dev"
  }

  assert {
    condition     = aws_iam_role.provisioner.name == "acme-dev-golden-path-provisioner"
    error_message = "The role name must follow name_prefix."
  }

  assert {
    condition     = local.state_bucket_arn == "arn:aws:s3:::acme-dev-tfstate-123456789012"
    error_message = "The state bucket must follow name_prefix."
  }
}

run "a_wildcard_resource_prefix_is_rejected" {
  command = plan

  variables {
    resource_prefix = "*"
  }

  expect_failures = [var.resource_prefix]
}

run "an_empty_resource_prefix_is_rejected" {
  command = plan

  variables {
    resource_prefix = ""
  }

  expect_failures = [var.resource_prefix]
}

run "a_wildcard_developer_name_is_rejected" {
  command = plan

  variables {
    developer_session_names = ["*"]
  }

  expect_failures = [var.developer_session_names]
}

run "a_state_prefix_without_a_trailing_slash_is_rejected" {
  command = plan

  variables {
    state_key_prefix = "golden-path"
  }

  expect_failures = [var.state_key_prefix]
}

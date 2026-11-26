# Plan-level tests for the root module. No AWS calls, no credentials.
#
# Two things worth guarding here:
#   1. The account guard actually fires. It is the safety net for running
#      as an administrator, and a safety net nobody has tested is decoration.
#   2. Resource names derive from client and environment. This is what makes
#      the stack reusable, and "we used variables" is not evidence — a
#      hardcoded name somewhere would still pass validate.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "tls" {}
mock_provider "random" {}

variables {
  allowed_account_id = "123456789012"
  # Pinned: `terraform test` also reads a local terraform.tfvars, and an environment that
  # sets this true would try to import real log groups inside a mocked plan.
  adopt_existing_log_groups = false
}

run "account_guard_passes_on_the_expected_account" {
  command = plan

  assert {
    condition     = local.name_prefix == "omf-dev"
    error_message = "Default prefix should be omf-dev, matching the issue."
  }
}

run "account_guard_blocks_the_wrong_account" {
  command = plan

  variables {
    allowed_account_id = "999999999999"
  }

  # The mocked caller identity is 123456789012, so the precondition must fail.
  # If this test ever passes without an expected failure, the guard is not
  # wired to anything.
  expect_failures = [terraform_data.account_guard]
}

run "account_id_must_be_twelve_digits" {
  command = plan

  variables {
    allowed_account_id = "not-an-account"
  }

  expect_failures = [var.allowed_account_id]
}

run "names_derive_from_client_and_environment" {
  command = plan

  variables {
    client             = "acme"
    environment        = "staging"
    allowed_account_id = "123456789012"
  }

  assert {
    condition     = local.name_prefix == "acme-staging"
    error_message = "Prefix must come from client and environment, not be hardcoded."
  }

  assert {
    condition     = local.backstage_cluster_name == "acme-staging-backstage"
    error_message = "Cluster names must derive from the prefix."
  }

  assert {
    condition     = local.argo_cluster_name == "acme-staging-argo"
    error_message = "Cluster names must derive from the prefix."
  }

  # The client tag is what makes resources attributable when more than one
  # deployment shares an account.
  assert {
    condition     = local.common_tags["client"] == "acme"
    error_message = "Tags must carry the client."
  }

  assert {
    condition     = local.common_tags["managed-by"] == "terraform"
    error_message = "AC #14: every resource carries managed-by=terraform."
  }
}

run "client_name_is_validated" {
  command = plan

  variables {
    client             = "Not Valid"
    allowed_account_id = "123456789012"
  }

  expect_failures = [var.client]
}

run "tls_defaults_to_option_b" {
  command = plan

  assert {
    condition     = output.tls_mode == "B (self-signed certificate on ALB hostname)"
    error_message = "With no domain_name the stack should fall back to Option B."
  }
}

# --- Cross-ticket contracts (found by reading issues #1 and #4 against #5) ----

# Issue #4 deploys from a GitHub Environment named `dev`. A job that declares an
# environment presents the subject `environment:dev`, not `ref:refs/heads/dev`,
# so a role trusting only branches fails at AssumeRoleWithWebIdentity. Asserting
# on the subjects the role actually trusts, not on the variable that feeds them.
#
# The literals below are the subject GitHub really sends — copied from the
# CloudTrail record of the first denied workflow run, not derived from a variable.
# This repository issues IMMUTABLE subject claims (numeric owner and repo ids). An
# earlier version of this test pinned the classic `repo:Oteemo/backstage-app:...`
# form, passed, and guarded a role that no workflow could assume.
run "ci_role_trusts_the_dev_github_environment" {
  command = plan

  assert {
    condition     = contains(module.github_oidc.allowed_subjects, "repo:Oteemo@19363462/backstage-app@1435925066:environment:dev")
    error_message = "The CI role must trust the `dev` GitHub Environment, or issue #4's deploy job cannot assume it."
  }

  assert {
    condition     = contains(module.github_oidc.allowed_subjects, "repo:Oteemo@19363462/backstage-app@1435925066:ref:refs/heads/dev")
    error_message = "Branch-based trust must still work alongside the environment."
  }

  assert {
    condition     = alltrue([for s in module.github_oidc.allowed_subjects : !can(regex("\\*", s))])
    error_message = "No wildcard subjects: a wildcard lets a fork's pull request assume the role."
  }
}

# Backstage reaches Argo over the public ALB from inside the VPC, so it arrives
# from the NAT gateway. Restricting the UI to one address must not lock out the
# Scaffolder's handoff to Argo (issue #1).
run "restricting_argo_keeps_the_nat_gateway_allowed" {
  command = plan

  variables {
    argo_inbound_cidrs = ["203.0.113.5/32"]
  }

  assert {
    condition     = local.argo_inbound_cidrs[0] == "203.0.113.5/32"
    error_message = "The operator's CIDR must be kept."
  }

  assert {
    condition     = length(local.argo_inbound_cidrs) == length(var.argo_inbound_cidrs) + length(module.network.nat_public_ips)
    error_message = "Every NAT gateway address must be allowed alongside the operator's CIDR."
  }
}

# The reverse matters just as much: empty means unrestricted, and that has to
# stay visible rather than being silently turned into "only the NAT can reach it".
run "unrestricted_argo_stays_visibly_unrestricted" {
  command = plan

  # Pinned, not left to the default: `terraform test` also reads a local
  # terraform.tfvars, so an unpinned run passes in CI (no tfvars) and fails on
  # any machine that has real values set.
  variables {
    argo_inbound_cidrs = []
  }

  assert {
    condition     = length(local.argo_inbound_cidrs) == 0
    error_message = "With no CIDRs set the allowlist must stay empty, not collapse to just the NAT address."
  }
}

# Belt and braces for the same failure: the default prefix must be the immutable
# form (owner and repo each followed by @<numeric id>), and the classic form must
# not be trusted at all.
run "ci_role_trusts_the_form_github_sends_and_not_the_classic_one" {
  command = plan

  assert {
    condition     = can(regex("^repo:[^/@]+@[0-9]+/[^:@]+@[0-9]+$", var.github_subject_prefix))
    error_message = "The default subject prefix must be the immutable form repo:<org>@<owner-id>/<repo>@<repo-id>."
  }

  assert {
    condition     = !anytrue([for s in module.github_oidc.allowed_subjects : startswith(s, "repo:Oteemo/backstage-app:")])
    error_message = "The classic subject form is never sent by this repository; trusting it widens the policy for nothing."
  }
}

# --- Log groups: Terraform owns them, and they are bounded ----------------------
# EKS and RDS create their log groups implicitly: no retention, no tags, invisible to
# Terraform, left behind by destroy. Asserting on what each module reports it owns —
# the names have to match exactly what EKS and RDS would otherwise create themselves,
# or the "owned" group is a different, empty one and the implicit one still leaks.
run "log_groups_are_owned_with_the_names_eks_and_rds_would_create" {
  command = plan

  assert {
    condition     = module.backstage_cluster.log_group_name == "/aws/eks/omf-dev-backstage/cluster"
    error_message = "The Backstage cluster log group must be exactly the one EKS would create."
  }

  assert {
    condition     = module.argo_cluster.log_group_name == "/aws/eks/omf-dev-argo/cluster"
    error_message = "The Argo cluster log group must be exactly the one EKS would create."
  }

  assert {
    condition = module.database.log_group_names == tolist([
      "/aws/rds/instance/omf-dev-backstage/postgresql",
      "/aws/rds/instance/omf-dev-backstage/upgrade",
    ])
    error_message = "Both exported RDS logs need an owned group — the `upgrade` one only appears at the first upgrade, so it would otherwise leak later."
  }
}

run "log_groups_expire_by_default" {
  command = plan

  assert {
    condition = alltrue([
      module.backstage_cluster.log_group_retention_days == 30,
      module.argo_cluster.log_group_retention_days == 30,
      module.database.log_group_retention_days == 30,
    ])
    error_message = "Every owned log group must have a bounded retention; unbounded was the accidental behaviour."
  }
}

run "never_expire_is_rejected" {
  command = plan

  variables {
    log_retention_days = 0
  }

  expect_failures = [var.log_retention_days]
}

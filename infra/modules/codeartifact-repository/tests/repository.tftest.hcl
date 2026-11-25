# Plan-level tests. No AWS calls, no credentials.

mock_provider "aws" {}

variables {
  domain       = "gp-python-package"
  domain_owner = "123456789012"
  repository   = "my-package"
}

run "repository_is_created_in_the_shared_domain" {
  command = plan

  assert {
    condition     = aws_codeartifact_repository.this.domain == "gp-python-package" && aws_codeartifact_repository.this.repository == "my-package"
    error_message = "The repository must live in the named domain with the given name."
  }
}

run "description_has_a_default" {
  command = plan

  assert {
    condition     = aws_codeartifact_repository.this.description == "Repository my-package"
    error_message = "An empty description should fall back to a generated one."
  }
}

run "upstreams_are_added" {
  command = plan

  variables {
    upstreams = ["pypi-store"]
  }

  assert {
    condition     = length(aws_codeartifact_repository.this.upstream) == 1
    error_message = "Each upstream should be planned."
  }
}

run "a_bad_account_id_is_rejected" {
  command = plan

  variables {
    domain_owner = "not-an-account"
  }

  expect_failures = [var.domain_owner]
}

run "a_bad_repository_name_is_rejected" {
  command = plan

  variables {
    repository = "-bad"
  }

  expect_failures = [var.repository]
}

run "an_overlong_description_is_rejected" {
  command = plan

  variables {
    description = join("", [for i in range(1001) : "a"])
  }

  expect_failures = [var.description]
}

# Plan-level tests for the network module. No AWS calls, no cost.
#
# These encode the decisions that are easy to break silently. A missing subnet
# tag does not fail `validate` or `apply` — it fails much later, when an
# ingress sits pending and nobody knows why.

# Provider is mocked so these run with no AWS credentials and no API calls —
# they belong in CI on every pull request, where credentials should not be.
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
}

variables {
  name_prefix       = "omf-dev"
  eks_cluster_names = ["omf-dev-backstage", "omf-dev-argo"]
}

run "rejects_fewer_than_two_azs" {
  command = plan

  variables {
    az_count = 1
  }

  expect_failures = [var.az_count]
}

run "defaults_are_sane" {
  command = plan

  assert {
    condition     = length(local.azs) == 2
    error_message = "Should default to 2 AZs — EKS and the ALB both require two."
  }

  assert {
    condition     = length(local.public_subnets) == 2 && length(local.private_subnets) == 2
    error_message = "Should create one public and one private subnet per AZ."
  }

  assert {
    condition     = length(setintersection(toset(local.public_subnets), toset(local.private_subnets))) == 0
    error_message = "Public and private subnet CIDRs overlap."
  }
}

run "subnets_carry_load_balancer_controller_tags" {
  command = plan

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.tags["kubernetes.io/role/elb"] == "1"])
    error_message = "Public subnets need kubernetes.io/role/elb=1 or the ALB controller ignores them."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.tags["kubernetes.io/role/internal-elb"] == "1"])
    error_message = "Private subnets need kubernetes.io/role/internal-elb=1 for internal load balancers."
  }

  assert {
    condition = alltrue([
      for s in aws_subnet.public :
      s.tags["kubernetes.io/cluster/omf-dev-backstage"] == "shared" &&
      s.tags["kubernetes.io/cluster/omf-dev-argo"] == "shared"
    ])
    error_message = "Subnets must be tagged shared for every cluster that uses them."
  }
}

run "private_subnets_do_not_auto_assign_public_ips" {
  command = plan

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.map_public_ip_on_launch == false])
    error_message = "Private subnets must not auto-assign public IPs. Nodes and RDS live here."
  }
}

run "single_nat_gateway_by_default" {
  command = plan

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "Demo should use one NAT gateway. One per AZ roughly triples the ~$33/month cost."
  }
}

run "nat_per_az_when_requested" {
  command = plan

  variables {
    single_nat_gateway = false
    az_count           = 3
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "Disabling single_nat_gateway should give one NAT per AZ."
  }
}

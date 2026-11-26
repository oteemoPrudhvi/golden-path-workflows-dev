# Plan-level tests for the EKS cluster module. No AWS calls, no cost.

# Providers mocked so these run with no AWS credentials — suitable for CI
# on every pull request.
mock_provider "aws" {
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
}

mock_provider "tls" {
  mock_data "tls_certificate" {
    defaults = {
      certificates = [
        {
          sha1_fingerprint = "9e99a48a9960b14926bb7f3b02e22da2b0ab7280"
        }
      ]
    }
  }
}

variables {
  cluster_name   = "omf-dev-backstage"
  subnet_ids     = ["subnet-aaaaaaaaaaaaaaaaa", "subnet-bbbbbbbbbbbbbbbbb"]
  instance_types = ["t3.large"]
}

run "uses_api_access_entries_not_aws_auth" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API"
    error_message = "Cluster should use API authentication mode, not the legacy aws-auth ConfigMap."
  }
}

run "audit_logging_enabled" {
  command = plan

  assert {
    condition     = contains(aws_eks_cluster.this.enabled_cluster_log_types, "audit")
    error_message = "Audit logs are what you need when access breaks. Keep them on."
  }
}

run "nodes_land_in_the_given_subnets" {
  command = plan

  assert {
    condition     = length(aws_eks_node_group.this.subnet_ids) == 2
    error_message = "Node group should use both supplied subnets."
  }
}

run "ebs_csi_addon_present_by_default" {
  command = plan

  assert {
    condition     = contains(keys(local.addons), "aws-ebs-csi-driver")
    error_message = "EBS CSI should be installed by default."
  }

  assert {
    condition     = length(aws_iam_role.ebs_csi) == 1
    error_message = "EBS CSI needs its own IRSA role — it calls the EC2 API for volume operations."
  }
}

run "ebs_csi_can_be_disabled" {
  command = plan

  variables {
    enable_ebs_csi = false
  }

  assert {
    condition     = !contains(keys(local.addons), "aws-ebs-csi-driver")
    error_message = "Disabling enable_ebs_csi should drop the add-on."
  }

  assert {
    condition     = length(aws_iam_role.ebs_csi) == 0
    error_message = "Disabling the add-on should not leave an orphaned IAM role."
  }
}

run "argo_cluster_shape_differs_from_backstage" {
  command = plan

  variables {
    cluster_name   = "omf-dev-argo"
    instance_types = ["t3.medium"]
    desired_size   = 1
    max_size       = 4
  }

  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].max_size == 4
    error_message = "Argo cluster should be able to scale out for workflow bursts."
  }
}

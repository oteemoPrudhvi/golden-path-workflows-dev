# =============================================================================
# AWS LOAD BALANCER CONTROLLER — IAM
# =============================================================================
# This module exists because of a hole found in review: the stack produced a
# certificate and a set of ingress annotations, but nothing that creates an
# ALB. Terraform does not create the load balancer — the controller does, from
# a Kubernetes Ingress. Without the controller installed, ACs #6, #7 and #8
# cannot pass no matter how correct the certificate is.
#
# The IAM half lives here with the rest of the infrastructure; the Helm install
# is in envs/omf-dev-workloads, for the provider-configuration reason set out
# in that module's README.
#
# iam_policy.json is the upstream policy, taken verbatim from
# kubernetes-sigs/aws-load-balancer-controller v2.13.0. Not hand-written: the
# controller needs a wide and specific set of elbv2, ec2 and acm permissions,
# and a hand-rolled approximation fails in ways that surface as an ingress
# silently never provisioning.
# =============================================================================

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "this" {
  name        = "${var.cluster_name}-alb-controller"
  description = "AWS Load Balancer Controller for ${var.cluster_name} (upstream policy v2.13.0)"
  policy      = file("${path.module}/iam_policy.json")

  tags = var.tags
}

resource "aws_iam_role" "this" {
  name               = "${var.cluster_name}-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = merge(var.tags, { Name = "${var.cluster_name}-alb-controller" })
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}

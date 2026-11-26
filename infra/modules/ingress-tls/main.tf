# =============================================================================
# INGRESS TLS — certificates and DNS for Backstage and the Argo UI
# =============================================================================
# HTTPS is mandatory: Okta rejects any redirect URI that is not https://,
# except localhost. This module provides the certificate and DNS plumbing.
#
# IMPORTANT — Terraform does NOT create the ALB.
#   The AWS Load Balancer Controller creates it from a Kubernetes Ingress.
#   So this module produces a certificate ARN and (Option A) a hosted zone;
#   the ingress annotations consume them. That ordering is why Option A uses
#   ExternalDNS for records rather than Terraform aws_route53_record alias
#   entries — Terraform cannot know the ALB hostname at plan time because the
#   ALB does not exist until the ingress is applied.
#
# Two modes, selected by var.domain_name being set or empty.
# =============================================================================

locals {
  # Shared by both ingresses. The load-balancer-name is added per app, since
  # ALB names must be unique per account and region.
  #
  # No kubernetes.io/ingress.class annotation: deprecated in favour of
  # spec.ingressClassName, which the ingress resources set.
  base_annotations = {
    "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
    "alb.ingress.kubernetes.io/target-type"     = "ip"
    "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
    "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
    "alb.ingress.kubernetes.io/certificate-arn" = var.domain_name != "" ? aws_acm_certificate.custom_domain[0].arn : aws_acm_certificate.self_signed[0].arn
  }

  use_custom_domain = var.domain_name != ""

  backstage_fqdn = local.use_custom_domain ? "${var.backstage_subdomain}.${var.domain_name}" : null
  argo_fqdn      = local.use_custom_domain ? "${var.argo_subdomain}.${var.domain_name}" : null

  manage_external_dns = local.use_custom_domain && var.oidc_provider_arn != null
}

# =============================================================================
# OPTION A — custom domain, DNS-validated ACM certificate
# =============================================================================

resource "aws_route53_zone" "this" {
  count = local.use_custom_domain && var.create_hosted_zone ? 1 : 0

  name = var.domain_name
  tags = merge(var.tags, { Name = "${var.name_prefix}-zone" })
}

data "aws_route53_zone" "existing" {
  count = local.use_custom_domain && !var.create_hosted_zone ? 1 : 0

  name         = var.domain_name
  private_zone = false
}

locals {
  zone_id = local.use_custom_domain ? (
    var.create_hosted_zone ? aws_route53_zone.this[0].zone_id : data.aws_route53_zone.existing[0].zone_id
  ) : null
}

# A wildcard covers both subdomains and anything added later without
# reissuing. ACM certificates are free; the cost is in the validation
# round trip, so one cert beats two.
# Wildcard only, no apex SAN.
#
# Two reasons. The hostnames we need (omf-backstage.<domain>, omf-argo.
# <domain>) are both covered by the wildcard, and the apex is unused. And a
# single-domain certificate produces exactly ONE validation record, which
# lets the record below use `count` rather than `for_each` over
# domain_validation_options — a set whose keys are not known at plan time.
# That for_each is a well-known source of "Invalid for_each argument" on
# first apply. Avoiding it entirely is simpler than working around it.
resource "aws_acm_certificate" "custom_domain" {
  count = local.use_custom_domain ? 1 : 0

  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  # Replacement certs must exist before the old one is detached from the
  # listener, otherwise the ALB briefly has no certificate.
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-cert" })
}

locals {
  # Exactly one option, because the certificate has a single domain.
  validation_option = local.use_custom_domain ? tolist(aws_acm_certificate.custom_domain[0].domain_validation_options)[0] : null
}

resource "aws_route53_record" "validation" {
  count = local.use_custom_domain ? 1 : 0

  zone_id = local.zone_id
  name    = local.validation_option.resource_record_name
  type    = local.validation_option.resource_record_type
  records = [local.validation_option.resource_record_value]
  ttl     = 60

  # ACM reuses the same validation record name across reissues. Without
  # this, a certificate replacement fails on the record already existing.
  allow_overwrite = true
}

# Blocks until ACM confirms the DNS records. Without this, the certificate
# can be referenced by an ingress before it is usable, and the ALB comes up
# with no valid cert.
resource "aws_acm_certificate_validation" "custom_domain" {
  count = local.use_custom_domain ? 1 : 0

  certificate_arn         = aws_acm_certificate.custom_domain[0].arn
  validation_record_fqdns = [aws_route53_record.validation[0].fqdn]
}

# --- ExternalDNS IRSA role ---------------------------------------------------
# ExternalDNS watches Ingress resources and writes the Route 53 records
# pointing at whatever ALB the controller created. This is what resolves the
# ordering problem described at the top of this file.
data "aws_iam_policy_document" "external_dns_assume" {
  count = local.manage_external_dns ? 1 : 0

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
      values   = ["system:serviceaccount:${var.external_dns_namespace}:${var.external_dns_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "external_dns" {
  count = local.manage_external_dns ? 1 : 0

  # Scoped to this hosted zone only. The default ExternalDNS policy in most
  # guides grants ChangeResourceRecordSets on "*", which lets it rewrite
  # every zone in the account.
  statement {
    sid       = "ChangeRecordsInOwnZoneOnly"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${local.zone_id}"]
  }

  # List operations take no resource — the API is account-wide by design.
  statement {
    sid    = "ListZones"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "external_dns" {
  count = local.manage_external_dns ? 1 : 0

  name               = "${var.name_prefix}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume[0].json
  tags               = merge(var.tags, { Name = "${var.name_prefix}-external-dns" })
}

resource "aws_iam_role_policy" "external_dns" {
  count = local.manage_external_dns ? 1 : 0

  name   = "${var.name_prefix}-external-dns-policy"
  role   = aws_iam_role.external_dns[0].id
  policy = data.aws_iam_policy_document.external_dns[0].json
}

# =============================================================================
# OPTION B — no domain, self-signed certificate imported into ACM
# =============================================================================
# A documented workaround, not a recommendation. Three things make it worse
# than Option A, and they are worth stating rather than discovering:
#
#   1. Every user gets a browser certificate warning, every new browser.
#   2. ACM cannot issue a public certificate for *.elb.amazonaws.com, hence
#      the import. Imported certificates do NOT auto-renew — this one expires
#      and someone has to notice.
#   3. The Okta redirect URI and Backstage baseUrl are the ALB's generated
#      hostname. If the ingress is deleted and recreated the ALB name changes,
#      and both break. Pin alb.ingress.kubernetes.io/load-balancer-name and do
#      not recreate the ingress.
#
# Automation against Option B must skip certificate verification (curl -k).
# =============================================================================

resource "tls_private_key" "self_signed" {
  count = local.use_custom_domain ? 0 : 1

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "self_signed" {
  count = local.use_custom_domain ? 0 : 1

  private_key_pem = tls_private_key.self_signed[0].private_key_pem

  subject {
    common_name  = "*.${data.aws_region.current.region}.elb.amazonaws.com"
    organization = var.name_prefix
  }

  # The SAN is what browsers actually check. Covers any ALB hostname in this
  # region, so the certificate survives an ALB being recreated even though
  # the URLs would not.
  dns_names = [
    "*.${data.aws_region.current.region}.elb.amazonaws.com",
  ]

  validity_period_hours = var.self_signed_validity_days * 24

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "self_signed" {
  count = local.use_custom_domain ? 0 : 1

  private_key      = tls_private_key.self_signed[0].private_key_pem
  certificate_body = tls_self_signed_cert.self_signed[0].cert_pem

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-self-signed-cert"
    # Tagged so it is obvious in the console why an untrusted certificate
    # exists, and that it will not renew itself.
    "renewal" = "manual-import-does-not-auto-renew"
  })
}

data "aws_region" "current" {}

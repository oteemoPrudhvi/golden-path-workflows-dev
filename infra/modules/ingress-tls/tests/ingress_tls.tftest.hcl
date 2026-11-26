# Plan-level tests. No AWS calls, no credentials.
#
# The point of these is that the two options are genuinely both supported —
# AC #6 and #7 require either to work from the same code.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_route53_zone" {
    defaults = {
      zone_id = "Z0123456789ABCDEFGHIJ"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

}

mock_provider "tls" {}

variables {
  name_prefix = "omf-dev"
}

run "option_b_is_the_default" {
  command = plan

  assert {
    condition     = local.use_custom_domain == false
    error_message = "With no domain_name, the module should fall back to Option B."
  }

  assert {
    condition     = length(tls_self_signed_cert.self_signed) == 1
    error_message = "Option B must generate a self-signed certificate."
  }

  assert {
    condition     = length(aws_acm_certificate.custom_domain) == 0
    error_message = "Option B must not create a DNS-validated certificate."
  }
}

run "option_b_pins_the_alb_name" {
  command = plan

  # The ALB hostname is the Okta redirect URI and Backstage baseUrl under
  # Option B. A recreated ALB gets a new name and breaks both.
  assert {
    condition     = contains(keys(output.backstage_ingress_annotations), "alb.ingress.kubernetes.io/load-balancer-name")
    error_message = "Option B must pin the load balancer name."
  }

  assert {
    condition     = output.smoke_test_tls_flag == "-k"
    error_message = "Option B is self-signed, so smoke tests must skip verification."
  }
}

run "option_a_when_domain_is_set" {
  command = plan

  variables {
    domain_name = "omf-idx-demo.click"
  }

  assert {
    condition     = local.use_custom_domain == true
    error_message = "Setting domain_name should select Option A."
  }

  assert {
    condition     = length(aws_acm_certificate.custom_domain) == 1
    error_message = "Option A must create a DNS-validated certificate."
  }

  assert {
    condition     = length(tls_self_signed_cert.self_signed) == 0
    error_message = "Option A must not generate a self-signed certificate."
  }

  assert {
    condition     = output.backstage_hostname == "omf-backstage.omf-idx-demo.click"
    error_message = "Backstage hostname should be <subdomain>.<domain>."
  }

  assert {
    condition     = output.argo_hostname == "omf-argo.omf-idx-demo.click"
    error_message = "Argo hostname should be <subdomain>.<domain>."
  }

  assert {
    condition     = output.smoke_test_tls_flag == ""
    error_message = "Option A uses a trusted certificate; smoke tests should verify normally."
  }
}

# AC #8 — applies to both options.
run "http_redirects_to_https_in_both_modes" {
  command = plan

  assert {
    condition     = output.backstage_ingress_annotations["alb.ingress.kubernetes.io/ssl-redirect"] == "443"
    error_message = "HTTP must redirect to HTTPS."
  }
}

run "http_redirects_to_https_under_option_a_too" {
  command = plan

  variables {
    domain_name = "omf-idx-demo.click"
  }

  assert {
    condition     = output.backstage_ingress_annotations["alb.ingress.kubernetes.io/ssl-redirect"] == "443"
    error_message = "HTTP must redirect to HTTPS under Option A as well."
  }

  assert {
    condition     = output.backstage_base_url == "https://omf-backstage.omf-idx-demo.click"
    error_message = "baseUrl must match the HTTPS hostname in use."
  }
}

run "each_app_gets_its_own_alb_name" {
  command = plan

  # ALB names are unique per account and region. A single pinned name shared
  # by both ingresses means the second one silently never provisions.
  assert {
    condition     = output.backstage_ingress_annotations["alb.ingress.kubernetes.io/load-balancer-name"] != output.argo_ingress_annotations["alb.ingress.kubernetes.io/load-balancer-name"]
    error_message = "Backstage and Argo must have different ALB names."
  }
}

run "argo_ui_can_be_restricted_by_cidr" {
  command = plan

  variables {
    argo_inbound_cidrs = ["203.0.113.0/24"]
  }

  # The Argo server runs without login in this demo, so an open ALB lets
  # anyone with the hostname submit workflows.
  assert {
    condition     = output.argo_ingress_annotations["alb.ingress.kubernetes.io/inbound-cidrs"] == "203.0.113.0/24"
    error_message = "argo_inbound_cidrs should restrict the Argo ALB."
  }

  assert {
    condition     = !contains(keys(output.backstage_ingress_annotations), "alb.ingress.kubernetes.io/inbound-cidrs")
    error_message = "Backstage should not inherit the Argo CIDR restriction."
  }
}

run "no_deprecated_ingress_class_annotation" {
  command = plan

  assert {
    condition     = !contains(keys(output.backstage_ingress_annotations), "kubernetes.io/ingress.class")
    error_message = "kubernetes.io/ingress.class is deprecated; use spec.ingressClassName."
  }

  assert {
    condition     = output.ingress_class_name == "alb"
    error_message = "ingress_class_name should be exposed for spec.ingressClassName."
  }
}

# The controller sets no Name tag on the ALB, its security group or its target
# groups, so in the console they show as "-" and cannot be told apart from the
# other stacks sharing the account. Asserting on the annotation each ingress is
# actually given, and that the two apps do not share a name.
run "each_app_alb_is_named" {
  command = plan

  assert {
    condition     = output.backstage_ingress_annotations["alb.ingress.kubernetes.io/tags"] == "Name=${var.name_prefix}-backstage-alb"
    error_message = "The Backstage ingress must name its ALB resources."
  }

  assert {
    condition     = output.argo_ingress_annotations["alb.ingress.kubernetes.io/tags"] == "Name=${var.name_prefix}-argo-alb"
    error_message = "The Argo ingress must name its ALB resources."
  }

  assert {
    condition     = output.backstage_ingress_annotations["alb.ingress.kubernetes.io/tags"] != output.argo_ingress_annotations["alb.ingress.kubernetes.io/tags"]
    error_message = "The two apps must not share a Name, or the console cannot tell them apart."
  }
}

# The public certificate is what lets an in-cluster client (Backstage calling Argo) trust
# the self-signed load balancer certificate without turning certificate checks off.
run "option_b_exposes_the_public_certificate_for_trust" {
  # apply, not plan: the certificate only exists after apply. The providers are mocked, so
  # nothing is created anywhere; the mock fills in a generated value to assert against.
  command = apply

  assert {
    condition     = output.self_signed_certificate_pem != null
    error_message = "Under Option B the module must expose the certificate it generated, so clients can trust it."
  }
}

run "option_a_has_no_self_signed_certificate_to_trust" {
  command = plan

  variables {
    domain_name = "omf-idx-demo.click"
  }

  assert {
    condition     = output.self_signed_certificate_pem == null
    error_message = "Under Option A the certificate is publicly trusted; there is nothing to add."
  }
}

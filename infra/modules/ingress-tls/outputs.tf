output "mode" {
  description = "Which option is active, for the README and smoke tests."
  value       = local.use_custom_domain ? "A (custom domain, trusted certificate)" : "B (self-signed certificate on ALB hostname)"
}

output "certificate_arn" {
  description = <<-EOT
    ACM certificate ARN for the ALB HTTPS listener.

    Goes on the Ingress as:
      alb.ingress.kubernetes.io/certificate-arn: <this value>
  EOT
  value       = local.use_custom_domain ? aws_acm_certificate.custom_domain[0].arn : aws_acm_certificate.self_signed[0].arn
}

output "backstage_hostname" {
  description = <<-EOT
    Hostname for Backstage, or null under Option B.

    Under Option B the hostname is the ALB's generated name, which does not
    exist until the ingress is applied. Read it from the ingress after apply:
      kubectl get ingress -n backstage -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
  EOT
  value       = local.backstage_fqdn
}

output "argo_hostname" {
  description = "Hostname for the Argo Workflows UI, or null under Option B."
  value       = local.argo_fqdn
}

output "backstage_base_url" {
  description = <<-EOT
    Value for app.baseUrl and backend.baseUrl in app-config.

    Null under Option B — see backstage_hostname. AC #8 requires these to
    match the HTTPS hostnames actually in use.
  EOT
  value       = local.use_custom_domain ? "https://${local.backstage_fqdn}" : null
}

output "hosted_zone_id" {
  description = "Route 53 zone id, or null under Option B."
  value       = local.zone_id
}

output "external_dns_role_arn" {
  description = "IRSA role ARN for ExternalDNS, or null when not applicable."
  value       = local.manage_external_dns ? aws_iam_role.external_dns[0].arn : null
}

# Two load balancers, two names. ALB names are unique per account and region,
# so a single pinned name cannot serve both Backstage and Argo — found in
# review, and it would have surfaced as the second ingress silently failing
# to provision.
output "backstage_alb_name" {
  description = "Pinned ALB name for the Backstage ingress. Option B depends on this being stable."
  value       = "${var.name_prefix}-backstage"
}

output "argo_alb_name" {
  description = "Pinned ALB name for the Argo ingress."
  value       = "${var.name_prefix}-argo"
}

output "backstage_ingress_annotations" {
  description = <<-EOT
    Annotations for the Backstage Ingress.

    AC #8 requires HTTP to redirect to HTTPS; ssl-redirect and listen-ports
    are what implement it. Assembled here so the values cannot drift from
    what Terraform created.
  EOT
  value = merge(local.base_annotations, {
    "alb.ingress.kubernetes.io/load-balancer-name" = "${var.name_prefix}-backstage"
    # Names the ALB and the security group and target groups created for it.
    # The controller sets no Name tag itself, so they show as "-" in the console.
    "alb.ingress.kubernetes.io/tags" = "Name=${var.name_prefix}-backstage-alb"
  })
}

output "argo_ingress_annotations" {
  description = <<-EOT
    Annotations for the Argo Workflows Ingress.

    Includes inbound-cidrs when var.argo_inbound_cidrs is set. The Argo UI in
    server auth mode has no login, so an unrestricted internet-facing ALB
    would let anyone with the hostname submit workflows.
  EOT
  value = merge(
    local.base_annotations,
    {
      "alb.ingress.kubernetes.io/load-balancer-name" = "${var.name_prefix}-argo"
      "alb.ingress.kubernetes.io/tags"               = "Name=${var.name_prefix}-argo-alb"
    },
    length(var.argo_inbound_cidrs) > 0 ? {
      "alb.ingress.kubernetes.io/inbound-cidrs" = join(",", var.argo_inbound_cidrs)
    } : {},
  )
}

output "ingress_class_name" {
  description = "Value for Ingress spec.ingressClassName. The kubernetes.io/ingress.class annotation is deprecated."
  value       = "alb"
}

output "smoke_test_tls_flag" {
  description = <<-EOT
    Flag CI smoke tests need when calling these endpoints.

    Empty under Option A. Under Option B the certificate is self-signed, so
    verification must be skipped — issue #5 calls this out explicitly.
  EOT
  value       = local.use_custom_domain ? "" : "-k"
}

output "self_signed_certificate_pem" {
  description = <<-EOT
    The self-signed certificate (public part only) under Option B, null under Option A.

    Clients inside the cluster that call a load balancer by its generated hostname, such
    as Backstage calling Argo, will not trust a self-signed certificate on their own. This
    is the trust anchor to give them. It is a public certificate, not a secret; the private
    key never leaves the module.
  EOT
  value       = local.use_custom_domain ? null : tls_self_signed_cert.self_signed[0].cert_pem
}

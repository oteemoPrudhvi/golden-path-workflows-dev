# AC #7: "both apps are reachable over HTTPS at their ALB DNS names (output by
# Terraform)". These are the outputs that criterion asks for — previously they
# were null under Option B and the README told you to use kubectl.

output "backstage_url" {
  description = <<-EOT
    URL for Backstage.

    Under Option A this is the custom domain. Under Option B it is the ALB's
    generated hostname, resolved by a data lookup because the ALB name is
    pinned. This value is also the Okta redirect URI and Backstage's baseUrl.
  EOT
  value = try(
    local.infra.backstage_url,
    length(data.aws_lb.backstage) > 0 ? "https://${data.aws_lb.backstage[0].dns_name}" : null,
  )
}

output "argo_url" {
  description = "URL for the Argo Workflows UI."
  value = try(
    local.infra.argo_hostname != null ? "https://${local.infra.argo_hostname}" : null,
    var.create_ingresses ? "https://${data.aws_lb.argo[0].dns_name}" : null,
  )
}

output "backstage_alb_dns_name" {
  description = "Raw ALB hostname for Backstage."
  value       = length(data.aws_lb.backstage) > 0 ? data.aws_lb.backstage[0].dns_name : null
}

output "argo_alb_dns_name" {
  description = "Raw ALB hostname for Argo."
  value       = var.create_ingresses ? data.aws_lb.argo[0].dns_name : null
}

output "okta_redirect_uri" {
  description = <<-EOT
    Redirect URI to register in Okta (issue #2).

    Cannot be known before apply under Option B, which is the ordering
    dependency documented in the infra README: apply, read this, register in
    Okta, then deploy Backstage with a matching baseUrl.
  EOT
  value       = length(data.aws_lb.backstage) > 0 ? "https://${data.aws_lb.backstage[0].dns_name}/api/auth/okta/handler/frame" : null
}

output "argo_ui_is_unrestricted" {
  description = <<-EOT
    True when the Argo UI is reachable from anywhere.

    The Argo server runs without login in this demo, so an unrestricted ALB
    lets anyone with the hostname submit workflows. Surfaced as an output so
    it is visible rather than buried in a variable default.
  EOT
  value       = length(try(local.infra.argo_inbound_cidrs, [])) == 0
}

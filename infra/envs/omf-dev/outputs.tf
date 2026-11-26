# =============================================================================
# Outputs
#
# Grouped by who needs them: operators standing the stack up, the CI
# pipeline, and the Kubernetes manifests that come next.
# =============================================================================

output "region" {
  description = "Region everything was created in."
  value       = var.region
}

output "name_prefix" {
  description = "Prefix applied to every resource name."
  value       = local.name_prefix
}

# --- Clusters ----------------------------------------------------------------
output "backstage_cluster_name" {
  description = "Backstage EKS cluster name."
  value       = module.backstage_cluster.cluster_name
}

output "argo_cluster_name" {
  description = "Argo Workflows EKS cluster name."
  value       = module.argo_cluster.cluster_name
}

output "kubeconfig_commands" {
  description = "Run these to add both clusters to your kubeconfig."
  value = {
    backstage = module.backstage_cluster.kubeconfig_command
    argo      = module.argo_cluster.kubeconfig_command
  }
}

# --- Backstage configuration -------------------------------------------------
output "techdocs_bucket" {
  description = "TechDocs bucket, for techdocs.publisher in app-config."
  value       = module.backstage_support.techdocs_bucket
}

output "ecr_repository_url" {
  description = "Where CI pushes the Backstage image."
  value       = module.backstage_support.ecr_repository_url
}

output "backstage_service_account_annotation" {
  description = <<-EOT
    Annotation for the Backstage ServiceAccount. This is what makes IRSA
    work — without it the pod falls back to node credentials, which is the
    thing AC #10 exists to prevent.
  EOT
  value       = module.backstage_support.service_account_annotation
}

output "database_secret_name" {
  description = <<-EOT
    Secrets Manager secret holding the database connection details.

    The name, not the values. Referenced from an ExternalSecret so the
    credentials reach the pod as POSTGRES_* environment variables without
    ever appearing in a manifest.
  EOT
  value       = module.database.credentials_secret_name
}

output "database_endpoint" {
  description = "RDS endpoint. Reachable only from the Backstage cluster."
  value       = module.database.endpoint
}

# --- Ingress -----------------------------------------------------------------
output "tls_mode" {
  description = "Which certificate option is active."
  value       = module.ingress_tls.mode
}

output "backstage_ingress_annotations" {
  description = "Annotations for the Backstage Ingress, including certificate ARN and HTTP-to-HTTPS redirect."
  value       = module.ingress_tls.backstage_ingress_annotations
}

output "argo_ingress_annotations" {
  description = "Annotations for the Argo Ingress, including any inbound CIDR restriction."
  value       = module.ingress_tls.argo_ingress_annotations
}

output "ingress_class_name" {
  description = "Value for spec.ingressClassName."
  value       = module.ingress_tls.ingress_class_name
}

output "backstage_alb_name" {
  description = "Pinned ALB name for Backstage. Used to look the hostname up after apply."
  value       = module.ingress_tls.backstage_alb_name
}

output "argo_alb_name" {
  description = "Pinned ALB name for Argo."
  value       = module.ingress_tls.argo_alb_name
}

output "backstage_url" {
  description = <<-EOT
    Backstage URL under Option A, null under Option B.

    Under Option B the hostname is the ALB's generated name, which does not
    exist until the ingress is applied:
      kubectl get ingress -n backstage -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
  EOT
  value       = module.ingress_tls.backstage_base_url
}

output "argo_hostname" {
  description = "Argo Workflows UI hostname under Option A, null under Option B."
  value       = module.ingress_tls.argo_hostname
}

output "external_dns_role_arn" {
  description = "IRSA role for ExternalDNS. Null under Option B, which has no DNS to manage."
  value       = module.ingress_tls.external_dns_role_arn
}

output "smoke_test_tls_flag" {
  description = "Flag CI smoke tests need: empty under Option A, -k under Option B."
  value       = module.ingress_tls.smoke_test_tls_flag
}

# --- CI ----------------------------------------------------------------------
output "github_actions_role_arn" {
  description = "Role for aws-actions/configure-aws-credentials in the CI workflow."
  value       = module.github_oidc.role_arn
}

output "github_actions_trusted_subjects" {
  description = <<-EOT
    Exact OIDC subjects the CI role accepts.

    If a workflow fails with 'not authorized to perform
    sts:AssumeRoleWithWebIdentity', compare the sub claim in the failing run
    against this list — the mismatch is almost always a branch that is not
    on it.
  EOT
  value       = module.github_oidc.allowed_subjects
}

# --- Workloads (consumed by envs/omf-dev-workloads) --------------------------
output "argo_artifacts_bucket" {
  description = "S3 bucket for Argo workflow artifacts and archived logs."
  value       = module.argo_support.artifacts_bucket
}

output "argo_workflows_role_arn" {
  description = "IRSA role for the Argo controller and workflow pods."
  value       = module.argo_support.irsa_role_arn
}

output "external_secrets_role_arn" {
  description = "IRSA role for External Secrets Operator on the Backstage cluster."
  value       = module.backstage_support.external_secrets_role_arn
}

output "backstage_alb_controller_role_arn" {
  description = "IRSA role for the Backstage cluster's load balancer controller."
  value       = module.backstage_alb_controller.role_arn
}

output "argo_alb_controller_role_arn" {
  description = "IRSA role for the Argo cluster's load balancer controller."
  value       = module.argo_alb_controller.role_arn
}

output "vpc_id" {
  description = "VPC id. The load balancer controller Helm release needs it."
  value       = module.network.vpc_id
}

output "backstage_namespace" {
  description = "Namespace Backstage runs in."
  value       = var.backstage_namespace
}

output "argo_namespace" {
  description = "Namespace Argo Workflows runs in."
  value       = var.argo_namespace
}

output "argo_inbound_cidrs" {
  description = "CIDRs allowed to reach the Argo UI. Empty means unrestricted."
  value       = local.argo_inbound_cidrs
}

output "common_tags" {
  description = <<-EOT
    The standard tags (client, environment, project, owner, managed-by).

    Exposed so the workloads layer can give them to the load balancer
    controller. Resources the controller creates — the ALBs, their security
    groups and target groups — are not Terraform's, so provider default_tags
    never reach them; without this they carry no project/owner/environment tag.
  EOT
  value       = local.common_tags
}

output "ingress_certificate_pem" {
  description = <<-EOT
    The load balancers' self-signed certificate, public part only (null with a custom
    domain). The workloads layer gives it to the Backstage pod as a trusted CA so Backstage
    can call Argo over HTTPS without disabling certificate checks.
  EOT
  value       = module.ingress_tls.self_signed_certificate_pem
}

output "golden_path_provisioner_role_arn" {
  description = "Role the golden-path provisioning workflow runs as (IRSA). The workloads layer annotates its ServiceAccount with it."
  value       = module.golden_path_access.provisioner_role_arn
}

output "golden_path_boundary_policy_arn" {
  description = "Permission boundary every role the provisioner creates must carry (permissions_boundary)."
  value       = module.golden_path_access.boundary_policy_arn
}

output "golden_path_developer_role_arn" {
  description = "Role named developers assume to test the golden-path Terraform, or null when none are named."
  value       = module.golden_path_access.developer_role_arn
}

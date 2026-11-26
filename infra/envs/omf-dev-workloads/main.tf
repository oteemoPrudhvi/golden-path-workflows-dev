# =============================================================================
# WORKLOADS — controllers, Argo Workflows, External Secrets, ingresses
# =============================================================================
# Runs after envs/omf-dev. See README.md for why this is a separate root
# module rather than part of the infrastructure apply.
# =============================================================================

provider "aws" {
  region = var.region
}

data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = var.infra_state_key
    region = var.region
  }
}

locals {
  infra = data.terraform_remote_state.infra.outputs

  argo_cluster_name      = local.infra.argo_cluster_name
  backstage_cluster_name = local.infra.backstage_cluster_name
  argo_namespace         = local.infra.argo_namespace
  backstage_namespace    = local.infra.backstage_namespace

  # Option A installs ExternalDNS to manage Route 53 records. Under Option B
  # there is no zone to manage, so it is skipped.
  manage_dns = try(local.infra.external_dns_role_arn, null) != null
}

# --- Cluster auth -------------------------------------------------------------
# Read fresh on each run. EKS tokens expire after 15 minutes, so a stored one
# works during apply and fails on the next.
data "aws_eks_cluster" "argo" { name = local.argo_cluster_name }
data "aws_eks_cluster_auth" "argo" { name = local.argo_cluster_name }
data "aws_eks_cluster" "backstage" { name = local.backstage_cluster_name }
data "aws_eks_cluster_auth" "backstage" { name = local.backstage_cluster_name }

provider "helm" {
  alias = "argo"
  kubernetes = {
    host                   = data.aws_eks_cluster.argo.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.argo.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.argo.token
  }
}

provider "helm" {
  alias = "backstage"
  kubernetes = {
    host                   = data.aws_eks_cluster.backstage.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.backstage.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.backstage.token
  }
}

provider "kubernetes" {
  alias                  = "backstage"
  host                   = data.aws_eks_cluster.backstage.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.backstage.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.backstage.token
}

provider "kubernetes" {
  alias                  = "argo"
  host                   = data.aws_eks_cluster.argo.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.argo.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.argo.token
}

# =============================================================================
# AWS LOAD BALANCER CONTROLLER — both clusters
# =============================================================================
# Nothing creates an ALB without this. Terraform produces the certificate and
# the annotations; the controller is what turns an Ingress into a load
# balancer. Its absence was the reason ACs #6, #7 and #8 could not pass.
# =============================================================================

resource "helm_release" "alb_controller_backstage" {
  provider = helm.backstage

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.alb_controller_chart_version
  namespace  = "kube-system"

  timeout = 600
  wait    = true

  values = [yamlencode({
    clusterName = local.backstage_cluster_name
    region      = var.region
    vpcId       = local.infra.vpc_id

    # Applied to everything this controller creates (ALBs, listeners, their
    # security groups, target groups). Deliberately NO Name here: a default Name
    # outranks the per-ingress Name annotation — observed on the live ALBs, where
    # the annotation lost — so each ingress names its own resources instead.
    defaultTags = local.infra.common_tags

    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = local.infra.backstage_alb_controller_role_arn
      }
    }
  })]
}

resource "helm_release" "alb_controller_argo" {
  provider = helm.argo

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.alb_controller_chart_version
  namespace  = "kube-system"

  timeout = 600
  wait    = true

  values = [yamlencode({
    clusterName = local.argo_cluster_name
    region      = var.region
    vpcId       = local.infra.vpc_id

    # Applied to everything this controller creates (ALBs, listeners, their
    # security groups, target groups). Deliberately NO Name here: a default Name
    # outranks the per-ingress Name annotation — observed on the live ALBs, where
    # the annotation lost — so each ingress names its own resources instead.
    defaultTags = local.infra.common_tags

    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = local.infra.argo_alb_controller_role_arn
      }
    }
  })]
}

# =============================================================================
# EXTERNAL DNS — Option A only
# =============================================================================
# Writes the Route 53 records pointing at whatever ALB the controller created.
# This is what resolves the ordering problem: Terraform cannot know the ALB
# hostname at plan time because the ALB does not exist until the ingress is
# applied.
# =============================================================================

resource "helm_release" "external_dns" {
  count    = local.manage_dns ? 1 : 0
  provider = helm.backstage

  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = var.external_dns_chart_version
  namespace  = "kube-system"

  timeout = 600
  wait    = true

  values = [yamlencode({
    provider = { name = "aws" }
    sources  = ["ingress"]
    policy   = "upsert-only" # never delete records it did not create

    serviceAccount = {
      create = true
      name   = "external-dns"
      annotations = {
        "eks.amazonaws.com/role-arn" = local.infra.external_dns_role_arn
      }
    }
  })]
}

# =============================================================================
# ARGO WORKFLOWS
# =============================================================================

# Workflow pods run as this service account. The chart does not create it —
# workflow.serviceAccount.create defaults to false — so without this, workflow
# pods fall back to "default" with no IRSA, and AC #9 fails on the artifact
# even though the workflow succeeds.
resource "kubernetes_service_account" "argo_workflow" {
  provider = kubernetes.argo

  metadata {
    name      = "argo-workflow"
    namespace = local.argo_namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = local.infra.argo_workflows_role_arn
    }
  }

  depends_on = [helm_release.argo_workflows]
}

resource "helm_release" "argo_workflows" {
  provider = helm.argo

  name             = "argo-workflows"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-workflows"
  version          = var.argo_workflows_chart_version
  namespace        = local.argo_namespace
  create_namespace = true

  timeout = 600
  wait    = true

  values = [yamlencode({
    # TOP LEVEL, not under artifactRepository.s3. The chart's configmap
    # template reads .Values.useStaticCredentials, and when it is true (the
    # default) it dereferences accessKeySecret.key — which we do not set,
    # because the service accounts use IRSA. Leaving it default makes
    # `helm template` fail with a nil pointer, verified at version 0.45.19.
    useStaticCredentials = false

    controller = {
      parallelism = var.argo_workflow_parallelism

      # Only workflows that reference a WorkflowTemplate, and whose spec is the template's,
      # may run. Without this, anyone who can submit a workflow (the no-token path, or
      # Backstage's token) could write an inline workflow that mounts a secret in this
      # namespace or runs as a ServiceAccount with an IAM role. "Secure" also stops a
      # submitter overriding the ServiceAccount, which "Strict" alone does not.
      workflowRestrictions = {
        templateReferencing = "Secure"
      }

      # The controller writes archived logs, so it needs the artifact role too.
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = local.infra.argo_workflows_role_arn
        }
      }

      workflowDefaults = {
        spec = {
          serviceAccountName = "argo-workflow"
          ttlStrategy = {
            secondsAfterCompletion = 3600
            secondsAfterSuccess    = 900
            # Failed workflows are kept a day — that is when the logs matter.
            secondsAfterFailure = 86400
          }
          podGC = { strategy = "OnWorkflowSuccess" }
        }
      }
    }

    server = {
      enabled = true
      # Token login only. "client" accepts a Bearer token and runs the request as that
      # token's ServiceAccount, so what a caller can do is decided by Kubernetes RBAC
      # (charts/argo-submitter for Backstage). "server" is NOT listed any more: it let a
      # request with no token act as the Argo server itself, which can create
      # WorkflowTemplates, and a template can run as any ServiceAccount, including the one
      # that holds the golden-path IAM role. Found by testing on 10 Nov: the controller's
      # workflowRestrictions (Secure) does not stop a submitter choosing the ServiceAccount,
      # so the way to close it is to remove the unauthenticated door. Consequence: the Argo
      # UI asks for a token. Templates are applied by an administrator with kubectl.
      authModes   = ["client"]
      serviceType = "ClusterIP"
    }

    artifactRepository = {
      archiveLogs = true
      s3 = {
        bucket      = local.infra.argo_artifacts_bucket
        region      = var.region
        endpoint    = "s3.amazonaws.com"
        useSDKCreds = true
      }
    }
  })]

  # Install only after this cluster's load balancer controller is serving.
  # The controller registers a mutating webhook on every Service. A Service
  # created while it has no endpoints is rejected with "no endpoints available
  # for service aws-load-balancer-webhook-service" — which is exactly how the
  # first real apply failed, because nothing ordered these releases.
  depends_on = [helm_release.alb_controller_argo]
}

# The ServiceAccount the golden-path provisioning workflow runs as, annotated with the scoped
# IAM role (IRSA). Created only after Argo has the workflow restriction above, so there is
# no window where an inline workflow could pick this ServiceAccount. try(): the role output
# exists once the infra layer has been applied with it.
resource "kubernetes_service_account_v1" "golden_path_provisioner" {
  count    = try(local.infra.golden_path_provisioner_role_arn, null) != null ? 1 : 0
  provider = kubernetes.argo

  metadata {
    name      = "golden-path-provisioner"
    namespace = local.argo_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = local.infra.golden_path_provisioner_role_arn
    }
  }

  depends_on = [helm_release.argo_workflows]
}

# The identity Backstage uses to call Argo. A local chart for the same reason as eso-config:
# the token is generated by Kubernetes after the Secret exists, and a kubernetes_secret
# resource would read it back into Terraform state. A Helm release keeps only the manifests.
resource "helm_release" "argo_submitter" {
  provider = helm.argo

  name      = "argo-submitter"
  chart     = "${path.module}/charts/argo-submitter"
  namespace = local.argo_namespace

  timeout = 300
  wait    = true

  values = [yamlencode({
    namespace = local.argo_namespace
  })]

  # The Role grants access to argoproj.io resources, which exist once Argo is installed.
  depends_on = [helm_release.argo_workflows]
}

# =============================================================================
# EXTERNAL SECRETS
# =============================================================================

resource "kubernetes_namespace" "backstage" {
  provider = kubernetes.backstage
  metadata { name = local.backstage_namespace }
}

# The load balancers' self-signed certificate (public part), so the Backstage pod can trust
# Argo's address. Node ignores the system store for this, so the chart points
# NODE_EXTRA_CA_CERTS at this file. try(): the output exists once the infra layer has been
# applied with it, and a custom domain (trusted certificate) has nothing to add.
resource "kubernetes_config_map_v1" "argo_ca" {
  count    = try(local.infra.ingress_certificate_pem, null) != null ? 1 : 0
  provider = kubernetes.backstage

  metadata {
    name      = "argo-ca"
    namespace = local.backstage_namespace
  }

  data = {
    "ca.crt" = local.infra.ingress_certificate_pem
  }

  depends_on = [kubernetes_namespace.backstage]
}

resource "helm_release" "external_secrets" {
  provider = helm.backstage

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  namespace        = "external-secrets"
  create_namespace = true

  timeout = 600
  wait    = true

  values = [yamlencode({
    installCRDs = true
    serviceAccount = {
      annotations = {
        "eks.amazonaws.com/role-arn" = local.infra.external_secrets_role_arn
      }
    }
  })]

  # Install only after this cluster's load balancer controller is serving.
  # The controller registers a mutating webhook on every Service. A Service
  # created while it has no endpoints is rejected with "no endpoints available
  # for service aws-load-balancer-webhook-service" — which is exactly how the
  # first real apply failed, because nothing ordered these releases.
  depends_on = [helm_release.alb_controller_backstage]
}

# The operator alone does not deliver anything. A ClusterSecretStore tells it
# where to look, and an ExternalSecret says what to project where. Without
# both, AC #11's "injected at runtime" half is unmet — raised in review.
#
# Deployed as a local Helm chart, NOT kubernetes_manifest. That resource checks
# the kind against the live API at plan time, and these kinds only exist once
# the release above installs the CRDs — so on a clean checkout the plan itself
# failed with "no matches for kind ClusterSecretStore". Found by the first real
# plan; the mock-provider tests cannot see it. Helm defers the check to apply,
# by which point depends_on guarantees the CRDs are there.
resource "helm_release" "eso_config" {
  provider = helm.backstage

  name      = "eso-config"
  chart     = "${path.module}/charts/eso-config"
  namespace = local.backstage_namespace

  timeout = 300
  wait    = true

  values = [yamlencode({
    region            = var.region
    storeName         = "aws-secretsmanager"
    databaseSecretKey = local.infra.database_secret_name
    appSecrets = [
      { secretName = "backstage-github", envVar = "GITHUB_TOKEN", remoteKey = "${local.infra.name_prefix}/backstage/github-token" },
      { secretName = "backstage-okta-client-id", envVar = "AUTH_OKTA_CLIENT_ID", remoteKey = "${local.infra.name_prefix}/backstage/okta-client-id" },
      { secretName = "backstage-okta", envVar = "AUTH_OKTA_CLIENT_SECRET", remoteKey = "${local.infra.name_prefix}/backstage/okta-client-secret" },
      { secretName = "backstage-okta-domain", envVar = "AUTH_OKTA_DOMAIN", remoteKey = "${local.infra.name_prefix}/backstage/okta-domain" },
      { secretName = "backstage-okta-api-token", envVar = "OKTA_API_TOKEN", remoteKey = "${local.infra.name_prefix}/backstage/okta-api-token" },
      { secretName = "backstage-argo", envVar = "ARGO_TOKEN", remoteKey = "${local.infra.name_prefix}/backstage/argo-token" },
      { secretName = "backstage-backend", envVar = "BACKEND_SECRET", remoteKey = "${local.infra.name_prefix}/backstage/backend-secret" },
    ]
    operatorServiceAccount = {
      name      = "external-secrets"
      namespace = "external-secrets"
    }
  })]

  depends_on = [
    helm_release.external_secrets,
    kubernetes_namespace.backstage,
  ]
}

# =============================================================================
# INGRESSES — what actually causes an ALB to exist
# =============================================================================

resource "kubernetes_ingress_v1" "backstage" {
  count    = var.create_ingresses && var.create_backstage_ingress ? 1 : 0
  provider = kubernetes.backstage

  metadata {
    name        = "backstage"
    namespace   = local.backstage_namespace
    annotations = local.infra.backstage_ingress_annotations
  }

  spec {
    ingress_class_name = local.infra.ingress_class_name

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = var.backstage_service_name
              port { number = var.backstage_service_port }
            }
          }
        }
      }
    }
  }


  # Block until the controller has built the ALB and written its hostname back to
  # the Ingress status, so the aws_lb lookup below cannot race it. The first real
  # apply of this resource failed with "couldn't find resource" without it —
  # the same race Argo's ingress already guarded against; I fixed one and not the
  # other.
  wait_for_load_balancer = true

  depends_on = [
    helm_release.alb_controller_backstage,
    kubernetes_namespace.backstage,
  ]
}

resource "kubernetes_ingress_v1" "argo" {
  count    = var.create_ingresses ? 1 : 0
  provider = kubernetes.argo

  metadata {
    name        = "argo-workflows-server"
    namespace   = local.argo_namespace
    annotations = local.infra.argo_ingress_annotations
  }

  spec {
    ingress_class_name = local.infra.ingress_class_name

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argo-workflows-server"
              port { number = 2746 }
            }
          }
        }
      }
    }
  }

  # Block until the controller has provisioned the ALB and written its hostname
  # back to the Ingress status. Without this the aws_lb lookup below races the
  # controller and fails with "no matching ELB" on a perfectly healthy apply.
  wait_for_load_balancer = true

  depends_on = [helm_release.alb_controller_argo]
}

# --- ALB hostnames -----------------------------------------------------------
# AC #7 says the ALB DNS names are "output by Terraform". They were null under
# Option B, with the README telling you to run kubectl — raised in review.
# Because the names are pinned, a data lookup resolves them.
# The controller creates one shared "backend" security group per cluster, once,
# the first time an Ingress needs it, and never revisits its tags — so neither the
# controller's defaultTags nor an ingress annotation ever reaches it. After the
# first tagging fix those two groups were still the only blank rows in the
# console. aws_ec2_tag adds tags to a resource Terraform did not create without
# taking ownership of it; destroying this removes only these tags.
locals {
  lbc_backend_clusters = merge(
    var.create_ingresses && var.create_backstage_ingress ? { backstage = local.backstage_cluster_name } : {},
    var.create_ingresses ? { argo = local.argo_cluster_name } : {},
  )

  # One entry per (cluster, tag). Keys are static so for_each works even though
  # the security group id is only known after the lookup.
  lbc_backend_tags = merge([
    for app, cluster in local.lbc_backend_clusters : {
      for k, v in merge(local.infra.common_tags, { Name = "${cluster}-backend" }) :
      "${app}/${k}" => { app = app, key = k, value = v }
    }
  ]...)
}

data "aws_security_group" "lbc_backend" {
  for_each = local.lbc_backend_clusters

  filter {
    name   = "tag:elbv2.k8s.aws/cluster"
    values = [each.value]
  }
  filter {
    name   = "tag:elbv2.k8s.aws/resource"
    values = ["backend-sg"]
  }

  # Created lazily by the controller when the first Ingress is reconciled, which
  # the ingresses' wait_for_load_balancer has finished waiting on by now.
  depends_on = [kubernetes_ingress_v1.argo, kubernetes_ingress_v1.backstage]
}

resource "aws_ec2_tag" "lbc_backend" {
  for_each = local.lbc_backend_tags

  resource_id = data.aws_security_group.lbc_backend[each.value.app].id
  key         = each.value.key
  value       = each.value.value
}

data "aws_lb" "backstage" {
  count = var.create_ingresses && var.create_backstage_ingress ? 1 : 0
  name  = local.infra.backstage_alb_name

  depends_on = [kubernetes_ingress_v1.backstage]
}

data "aws_lb" "argo" {
  count = var.create_ingresses ? 1 : 0
  name  = local.infra.argo_alb_name

  depends_on = [kubernetes_ingress_v1.argo]
}

# Workloads — a separate root module, on purpose

Installs Argo Workflows and External Secrets Operator onto the clusters that
`envs/omf-dev` creates.

## Why this is not in `envs/omf-dev`

Terraform cannot reliably configure a provider using values produced by
resources in the same apply. The `helm` and `kubernetes` providers need the
cluster endpoint, CA certificate and an auth token — all of which are unknown
until the EKS cluster exists.

Terraform documents this as unsupported. In practice it half-works: the first
apply fails because the provider cannot be configured, and after that it
appears fine, which is worse than failing consistently. Destroy is where it
really hurts — the provider configuration becomes unreadable partway through
and the apply strands.

Splitting into two root modules removes the problem rather than working around
it. This module reads the first one's outputs through `terraform_remote_state`,
so by the time it plans, the clusters already exist and their details are known
values.

## Order

```bash
# 1. Infrastructure first
cd ../omf-dev
terraform apply

# 2. Then workloads
cd ../omf-dev-workloads
cp backend.hcl.example backend.hcl     # same bucket, different key
terraform init -backend-config=backend.hcl
terraform apply
```

Teardown is the reverse: destroy workloads before infrastructure, or the Helm
releases are orphaned and the cluster deletion blocks on finalizers.

## Things that behave differently from what you would expect

**Install order is explicit.** Argo and External Secrets declare
`depends_on` their cluster's load balancer controller. The controller registers
a webhook on every Service; one created while it has no endpoints is rejected.
Without the ordering the first apply fails with `no endpoints available for
service aws-load-balancer-webhook-service`.

**A failed Helm release is not recorded in state.** If an apply dies partway,
Helm may leave a release in `failed` status that Terraform does not know about,
and the retry then fails with "cannot re-use a name". `helm uninstall` it first.

**`eso-config` is a chart, not `kubernetes_manifest`.** That resource checks the
kind against the live API at plan time, and `ClusterSecretStore` only exists
after External Secrets installs, so a clean-checkout plan cannot succeed.

**The Backstage Ingress is on by default** (`create_backstage_ingress`). Its ALB
is built even though the `backstage` Service does not exist yet, and answers 503
until issue #4 deploys pods. That ordering is deliberate: Okta (issue #2) needs
the final hostname before Backstage is deployed. Set it false only to install
the controllers without exposing anything.

**Secrets are projected one ExternalSecret each** (`charts/eso-config`): the
database, plus GitHub, Okta and backend secrets. The last three stay in a sync
error until someone sets a value in Secrets Manager; separate objects mean each
becomes usable as soon as its own value exists.

**Lock the Argo UI.** It has no login. Set `argo_inbound_cidrs` in `envs/omf-dev`
and re-apply both layers; the CIDR travels through an ingress annotation.


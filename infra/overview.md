# Infrastructure as code: what we built and how

One document on the Terraform behind the OMF IDX proof of concept (issue #5):
what it creates, how it is organised, the decisions behind it, and how we know
it works. The detail lives in [README.md](README.md) (how to run
it) and [PROGRESS.md](PROGRESS.md) (the evidence, criterion by
criterion).

This is an Oteemo internal proof of concept. It runs in Oteemo's sandbox AWS
account (us-east-1). "OMF" is only the client name used as a resource prefix.

## What it creates

| What                                             | Why                                                                                                                       |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| One VPC, two availability zones, one NAT gateway | Shared by both clusters, so the Scaffolder can reach Argo without peering                                                 |
| **Two EKS clusters** (Kubernetes 1.35)           | `omf-dev-backstage` runs the portal. `omf-dev-argo` runs Argo Workflows. Kept apart so a heavy job cannot slow the portal |
| RDS Postgres, private and encrypted              | Backstage's database. Reachable only from the Backstage cluster                                                           |
| ECR repository                                   | Where the Backstage image is pushed and deployed from                                                                     |
| Two S3 buckets                                   | TechDocs (built by CI, read by the portal) and Argo workflow artifacts                                                    |
| Secrets Manager entries                          | Database, GitHub token, Okta values, backend secret and the Argo token. Delivered into the cluster by External Secrets    |
| Two ALBs with HTTPS                              | The only internet-facing parts. Self-signed certificate, because there is no domain                                       |
| GitHub OIDC role                                 | Lets GitHub Actions deploy with short-lived credentials and no stored keys                                                |
| In-cluster add-ons                               | AWS Load Balancer Controller, External Secrets Operator, Argo Workflows                                                   |
| Argo access for the golden path                  | A narrow identity for Backstage to call Argo, and a scoped AWS role for the provisioning workflow (see Security model)    |

## How it is organised

```
infra/
├── bootstrap/                state bucket, run once, local state
├── scripts/verify.sh         post-apply acceptance checks
├── envs/
│   ├── omf-dev/              infrastructure, applied first
│   └── omf-dev-workloads/    controllers, Argo, External Secrets, ingresses
└── modules/                  network, eks-cluster, rds-postgres,
                              backstage-support, argo-support, alb-controller,
                              ingress-tls, github-oidc
```

- **Modules hold no client values.** A second client is a new `envs/` folder and
  different variables. A test plans the whole stack under another name and checks
  every derived name follows.
- **Two root modules, not one.** The Helm and Kubernetes providers need the
  cluster endpoint and token, which do not exist until EKS does. Splitting
  removes the problem instead of working around it.
- **Remote state** in S3 with native locking. No DynamoDB table.

## The order we ran it

1. `bootstrap`: create the state bucket.
2. `envs/omf-dev`: network, both clusters, database, registry, buckets, secrets,
   certificate, GitHub role.
3. `envs/omf-dev-workloads`: load balancer controllers, External Secrets, Argo.
4. `scripts/verify.sh`: checks the live environment against the acceptance
   criteria.

Terraform is applied by hand by an administrator. No workflow applies it.

## Decisions and why

| Decision                                                               | Reason                                                                         |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Secrets created empty, values set out of band                          | Values never enter code, state or a plan file                                  |
| `recovery_window_in_days = 0` on secrets                               | The default 7–30 day hold makes destroy and re-apply cycles fail               |
| EKS access entries, not the `aws-auth` ConfigMap                       | The ConfigMap is edited by hand and drifts out of Terraform's view             |
| `StringEquals` on the GitHub OIDC subject, pinned to the repository ID | A wildcard would let a fork's PR assume a role that can push images and deploy |
| No domain (self-signed certificate)                                    | Decided 28 Oct. Browsers warn once. Consequences are documented                |
| Single NAT, single-AZ RDS                                              | About a third of the cost of HA. Documented trade-off for a 1–2 user demo      |

## Security model

- **Two identities, deliberately different.** An administrator runs Terraform.
  The CI role can only push to ECR, deploy to one namespace and publish docs to
  one S3 bucket. Administrator credentials never reach GitHub Actions.
- **CI role trust:** exact matches only, using GitHub's immutable subject claim:
  the `dev` and `master` branches (master is unused) and the `dev` GitHub
  Environment. Pull requests and feature branches cannot assume it.
- **In-cluster access:** an EKS access entry with the Edit policy scoped to the
  `backstage` namespace.
- **Argo accepts tokens only.** Since 10 Nov there is no unauthenticated mode. Backstage holds a
  token for one ServiceAccount that can read a single WorkflowTemplate and run workflows in one
  namespace; it cannot create templates. The controller only runs workflows that reference a
  template. The page is still limited by `argo_inbound_cidrs`.
- **Provisioning role, scoped by name.** The workflow that creates Python packages runs as a role
  that can only create IAM roles, CodeArtifact domains and repositories named `gp-…`, and use one
  prefix of the state bucket. Every role it creates must carry a permission boundary that allows
  CodeArtifact publishing only, and the boundary cannot be removed.
- **Certificate trust without turning checks off.** Backstage trusts the load balancers'
  self-signed certificate through a ConfigMap and `NODE_EXTRA_CA_CERTS`.
- **Known limit:** `PowerUserAccess` can read and write all secrets and delete
  clusters. Documented in the README.

## How we know it works

- **Terraform CI** on every change under `infra/`: format check, validate, tests
  that use mock providers (no AWS needed), and a check that no state or tfvars
  files are committed.
- **Tests:** 13 root-module tests plus module tests, including one that plans
  the stack as a second client.
- **Live checks:** `verify.sh` (15 checks pass from an allowlisted network).
- **Permission claims proven, not assumed:** the IAM policy simulator for what
  the CI role can and cannot do, and CloudTrail for the exact OIDC subject
  GitHub presents.
- **Used for real:** the CI/CD pipeline deployed Backstage onto this
  infrastructure, and a rollback drill passed on 2 Nov (see
  [pipeline.md](../deploy/pipeline.md)).

Acceptance criteria on #5: 12 met, 2 partly met (cost not measured, README not yet
walked through by someone else), 1 not applicable, 1 not run (the destroy, which goes
last).

## What went wrong on the way, and the fix

| Problem                                                           | Fix                                              |
| ----------------------------------------------------------------- | ------------------------------------------------ |
| A GitHub OIDC provider already existed in the account             | Variables to reuse it instead of creating one    |
| Kubernetes manifests failed at plan time, before the CRDs existed | Local Helm chart for the External Secrets config |
| Load balancer controller webhook had no endpoints yet             | Explicit `depends_on` on the controller          |
| Load balancer lookup raced the controller creating it             | Wait for the load balancer before reading it     |
| GitHub's OIDC subject is an immutable ID, not the repo name       | `subject_prefix` variable                        |
| Cost tagging covered clusters but not everything                  | Tagging fixes plus owned log groups              |
| Testing the Argo lockdown: a no-token request could create a template that runs as the provisioning ServiceAccount, and the controller restriction did not stop the ServiceAccount being chosen | Removed the no-token login mode; token only (#59) |

## Cost

About $377/month, or $12/day, if left running. The two EKS control planes are a
third of that. Estimated from the resource inventory, not measured: cost
allocation tags are not active in AWS.

## Not production ready

Single NAT, single-AZ database with no deletion protection or final snapshot,
Kubernetes API open to the internet by default, self-signed certificate, and
secrets that cannot be recovered after deletion. Each is a variable or a marked
line, listed in the README.

## Where to read more

- [README.md](README.md): prerequisites, bootstrap, apply,
  teardown, secrets and rotation, standing it up for another client.
- [PROGRESS.md](PROGRESS.md): evidence per criterion, decisions,
  defects, open questions.
- [pipeline.md](../deploy/pipeline.md): the CI/CD side, rollback and the drill.

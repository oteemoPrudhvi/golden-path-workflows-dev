# Issue #5 — Progress

Running record of what has been built, what has not, and why. Updated as work
lands, not reconstructed afterwards.

**Branch:** `infra/5-eks-clusters` · **PR:** #7 · **Last updated:** 29 October 2026

---

## Status in one line

Eight modules and two root modules, **applied to the Oteemo sandbox** (an Oteemo account,
not an OMF one) on 29 October and extended since: a proof of concept for OMF, not client
infrastructure. **Twelve of sixteen criteria are met** against live AWS; two are partly met
(#13 cost attribution, #15 a README walk-through by someone else), one is not applicable
(#6) and one is not run (#16, the destroy, which goes last). The rest of the project now
runs on it: Backstage is deployed through the pipeline (#4), Okta sign-in is live (#2), and
the Docs page is built by CI and read from S3. The environment is **running and costing
~$12/day**.

---

## Acceptance criteria

Legend: 🟢 met · 🟡 implemented, unverified or partly proven · 🔴 implemented and **shown not to work** · ➖ not applicable (an alternative that was not chosen) · ⚪ not started

| # | Criterion | |
|---|---|---|
| 1 | fmt / validate / tflint pass in CI for every module | 🟢 **Met.** PR #7, run 40725024016 — all 15 jobs green on first attempt |
| 2 | `plan` succeeds for dev from a clean checkout | 🟢 **Met.** Run against the Oteemo sandbox on 29 Oct. The first plan of the workloads layer failed (see "First apply") and was fixed |
| 3 | `apply` creates two EKS clusters, ACTIVE, nodes Ready | 🟢 **Met.** Both ACTIVE on 1.35; 3 nodes Ready (2 Backstage, 1 Argo). `verify.sh` passes |
| 4 | State remote, encrypted, locked; no state/tfvars committed | 🟢 **Met.** Bucket exists: AES256, versioned, public access blocked, native lockfile in use. CI check confirms nothing sensitive is tracked |
| 5 | RDS reachable from cluster, not from internet | 🟢 **Met.** A throwaway pod in the Backstage cluster opened a TCP connection to the database port. Not-from-internet: not publicly accessible, and its subnets have no internet-gateway route. Network reachability only — no login was attempted |
| 6 | Option A — HTTPS on custom domain, trusted cert | ➖ **Not applicable — Option B was chosen** (28 Oct: no domain). The issue defines A and B as alternatives (A: `domain_name` set; B: `domain_name` empty) and calls B acceptable for the demo. **Option A is implemented and unit-tested against mocks but has never been applied**: the Route 53 zone, the DNS-validated certificate and ExternalDNS are unproven. An earlier version of this row said the mechanism was "proven by Option B"; that overclaimed — B proves the ALB and certificate attachment, not A's DNS and validation path |
| 7 | Option B — HTTPS on ALB, self-signed | 🟢 **Met for both.** Each ALB is `active`, serves HTTPS with the self-signed certificate, and its URL is a Terraform output. Argo returns 200. Backstage returned 503 until its first deploy on 2 Nov; it now returns 200 on its home page with the target `healthy` |
| 8 | HTTP→HTTPS redirect; baseUrl matches | 🟢 **Met.** Plain HTTP returns 301 to HTTPS on both load balancers. The app's `baseUrl` (read from the running Deployment's environment) is **identical** to Terraform's `backstage_url` output, compared in code; the pipeline derives it from the same Ingress |
| 9 | Hello-world Argo workflow → S3 artifact | 🟢 **Met.** Workflow reached Succeeded; artifact in the artifacts bucket. `verify.sh` passes |
| 10 | Test pod reaches TechDocs via IRSA | 🟢 **Met.** A pod wrote to the TechDocs bucket using IRSA only. `verify.sh` passes |
| 11 | No secrets in code or state outputs | 🟢 **Met (9 Nov).** All four kinds are delivered and used: the database secret (five `POSTGRES_*` keys); the GitHub token (verified against GitHub: reads `backstage-app`, refused on three other private repos; expires 28 Dec); the backend secret (a random value stored without ever being displayed); and the Okta values (client ID, client secret, domain, API token), set by the Okta owner, read by the portal, with Okta sign-in working. Run logs scanned for key, token and password patterns across nine runs: nothing found. Caveats: the generated DB password is in the (encrypted) state file; and **people with Secrets Manager read access in the account can read the values**, because `PowerUserAccess` allows it, so "never displayed by us" is not "nobody can see it" |
| 12 | GitHub OIDC role, least privilege | 🟢 **Met, both subject paths.** Real runs from `dev` assumed the role by the **branch** subject (authorised for push-side ECR calls, deploy rights in the `backstage` namespace, and **denied** on another ECR repository, `kube-system` on both clusters, the `external-secrets` namespace and cluster-wide roles) and, since the GitHub Environment `dev` was created on 30 Oct, by the **`environment:dev`** subject too. The Environment allows deployments only from the `dev` branch (read back from GitHub). **Not tested:** the negative — that a run from another branch is refused by the Environment. The environment run proves assumption only; it reuses the same role and policy, so the denials were not repeated for it |
| 13 | Sizing matches + README cost estimate | 🟡 Cost corrected to ~$377; the $315 figure understated nodes by $62 |
| 14 | Consistent tags | 🟢 **Met, with one named exception.** A live audit found 54 tagged resources across 25 types all complete with a single `project` value; all 12 IAM roles tagged; the controller-created ALBs, target group and security groups carry a Name + all five tags (`verify.sh` checks them); the state bucket's tag is fixed; and the four CloudWatch log groups are now owned by Terraform with tags and a 30-day retention (verified in AWS, and a fresh plan shows no changes). **Exception:** load-balancer listener rules are untagged — sub-objects of the ALB that the controller does not tag and Terraform cannot, with no cost of their own; they are attributable through the tagged ALB. This exception was decided before the result was seen, and is not hidden |
| 15 | README: prerequisites, bootstrap, apply/destroy | 🟡 Rewritten after review — workloads apply, teardown order, diagram, corrected bootstrap advice |
| 16 | `destroy` removes everything cleanly | ⚪ Needs an apply first |

**🟢 12 · 🟡 2 · ➖ 1 · ⚪ 1**

---

## Scope items from the issue

| | Item | |
|---|---|---|
| 1 | Terraform foundation | ✅ |
| 2 | Networking | ✅ |
| 3 | Backstage EKS cluster | ✅ |
| 4 | Argo Workflows EKS cluster | ✅ Cluster, Helm install, artifact bucket and workflow IRSA |
| 5 | Backstage supporting resources | ✅ All resources, plus External Secrets Operator and its IRSA role |
| 6 | Ingress / DNS / TLS | ✅ Both options |
| 7 | IAM for CI/CD | ✅ |
| 8 | Documentation | ✅ README written |

---

## What exists

Eleven Terraform configurations — eight reusable modules, two root modules and
the bootstrap.

```
infra/
├── bootstrap/                 state bucket — run once, local state
├── envs/
│   ├── omf-dev/               AWS layer: VPC, clusters, RDS, IAM, ACM
│   └── omf-dev-workloads/     Kubernetes layer: Helm, Ingress, secrets
└── modules/
    ├── network/               VPC, 2 AZs, single NAT, ALB controller tags
    ├── eks-cluster/           reusable — instantiated twice
    ├── rds-postgres/          Backstage database
    ├── backstage-support/     TechDocs S3 + IRSA, ECR, Secrets Manager, ESO IRSA
    ├── argo-support/          artifact bucket + workflow IRSA
    ├── alb-controller/        upstream AWS LBC IAM policy v2.13.0, one role per cluster
    ├── ingress-tls/           Options A and B behind one variable
    └── github-oidc/           keyless CI credentials
```

The two root modules are split because Terraform cannot reliably configure a
provider from resource outputs produced in the same apply. `omf-dev-workloads`
reads `omf-dev` through `terraform_remote_state`. Apply order is bootstrap →
omf-dev → omf-dev-workloads; teardown is the reverse.

**11 commits · 73 files · ~6,390 lines · 31 tests across 5 modules**

CI (`.github/workflows/terraform-ci.yml`) runs 18 jobs: fmt, validate, tflint,
`terraform test` across the matrix, and a check that no state or tfvars is
committed. Needs no AWS credentials — tests use `mock_provider` — so it is safe
on PRs from any contributor.

---

## Option B — what this now commits us to

Decided 28 October: no domain. `domain_name = ""`, which selects the
self-signed certificate on the ALB's generated hostname. The module already
supports it and no code change is needed, but four things follow:

**Every user gets a browser certificate warning.** Expected, once per
browser. Worth saying in the demo script so it does not look like a fault.

**The certificate does not auto-renew.** Imported ACM certificates never do.
This one is valid 365 days from apply. Nothing will warn you — put a
reminder somewhere, or accept that a long-lived demo breaks silently.

**The ALB hostname is the Okta redirect URI and Backstage `baseUrl`.** If the
ingress is deleted and recreated, the ALB gets a new name and both break.
`alb.ingress.kubernetes.io/load-balancer-name` is pinned in the module for
exactly this reason — do not remove it, and do not recreate the ingress
casually.

**Ordering dependency with issue #2 (Okta integration).** The redirect URI
cannot be registered in Okta until the ALB exists, because its hostname is
not known until then. So the sequence is: apply infrastructure → read the
ALB hostname from the ingress → register it in Okta → deploy Backstage with
the matching `baseUrl`. Worth raising with whoever picks up #2, since it
means Okta configuration cannot be prepared in advance.

CI smoke tests against these endpoints must skip certificate verification.
The `smoke_test_tls_flag` output returns `-k` in this mode so the flag comes
from Terraform rather than being hardcoded in a workflow.

---

## Review response — 29 October

Five blockers, all verified before fixing rather than taken on trust.

| | Finding | Resolution |
|---|---|---|
| 1 | Argo Helm install fails — `nil pointer` on `accessKeySecret.key` | Confirmed by rendering the chart. `useStaticCredentials = false` is a **top-level** value, not nested under `artifactRepository.s3` as suggested; the suggested path still failed |
| 2 | Argo IRSA never wired | Confirmed. Chart creates `argo-workflows-workflow-controller`, not `argo-workflows-controller`. Service account now created and annotated; controller annotated too |
| 3 | No load balancer controller, ExternalDNS or Ingress anywhere | Confirmed and the most serious. New `alb-controller` module, Helm installs for both clusters, ExternalDNS under Option A, and real Ingress resources |
| 4 | `verify.sh` IRSA check fails by design | Confirmed — pod ran as `irsa-check:irsa-check`, role trusts `backstage:backstage`. Fixed, plus `-i` for stdin and stderr no longer discarded |
| 5 | Kubernetes 1.31 is in EKS extended support | Confirmed against AWS docs: standard support is 1.34–1.37. Default now 1.35, with a validation rule rejecting known extended-support versions |

**Blocker 3 is the one worth dwelling on.** The tests passed because they
asserted on strings in a Terraform output — not that anything consumed them.
Nothing created an ALB, so ACs #6, #7 and #8 could not pass however correct the
certificate was. Testing the artifact produced rather than the outcome required
is exactly the failure mode this document is supposed to guard against.

Also addressed: EKS access entries for CI, ClusterSecretStore and
ExternalSecret, per-app ALB names (one pinned name cannot serve two clusters),
Argo UI CIDR restriction, committed lock files, corrected cost, architecture
diagram, and seven nits.

---

## First apply — 29 October

Six defects that 18 green CI jobs could not see, because mock providers know
nothing about what already exists in an account or how a live API behaves — plus
item 4, which was **my own wrong assumption**, caught by a probe and reversed
(below).

| | Found by | Defect | Fix |
|---|---|---|---|
| 1 | `terraform apply` | GitHub OIDC provider already exists in the account (created 24 Apr by another stack); AWS allows one per URL → `EntityAlreadyExists`. The module supported reuse but the root never passed it through | `github_create_oidc_provider` and `github_existing_oidc_provider_arn` exposed at the root. Default unchanged for a fresh account |
| 2 | `terraform plan` | `kubernetes_manifest` checks the kind against the live API **at plan time**; `ClusterSecretStore` only exists once External Secrets installs in the same apply → a clean-checkout plan could never succeed | Moved to a small local Helm chart (`charts/eso-config`) installed after the operator. No new provider |
| 3 | `terraform apply` | Argo and External Secrets installed concurrently with the load balancer controller; its webhook rejected their Services (`no endpoints available`). Nothing ordered them | `depends_on` the cluster's controller release. Two orphaned failed releases had to be uninstalled first, since Terraform had not recorded them |
| 4 | A probe, 29 Oct (a wrong assumption of mine) | I assumed the load balancer controller builds no ALB for an Ingress whose backend Service does not exist, and gated the Backstage Ingress off on that basis. **The assumption was wrong:** the controller assigned a hostname in ~10s and logged `SuccessfullyReconciled`. The gate would have hidden the Backstage URL that issue #2 (Okta) needs before Backstage is deployed | `create_backstage_ingress` now defaults to **true**. The ALB exists first and answers 503 until #4 deploys pods |
| 5 | `terraform apply` (second workloads apply) | The same ALB-lookup race as Argo, on the Backstage ingress: the `aws_lb` data source ran before the controller had built the ALB (`couldn't find resource`). I had guarded Argo's ingress against this and not Backstage's — fixing one instance of a known problem instead of searching for the class. Incidentally the first live confirmation that the ALB is built without a Service | `wait_for_load_balancer` on the Backstage ingress too |
| 6 | Noticed from a screenshot of the console, then confirmed by a live check | The ALBs, target groups and security groups the load balancer controller creates carried **no standard tags and no Name** — 13 resources across the two clusters. Terraform's provider `default_tags` cannot reach resources it did not create. I had marked AC #14 met on a check that covered the clusters only, and said so in the row, but not loudly enough: the criterion is about consistent tags, not the two resources I chose to look at | Took **two fixes**. The first (controller `defaultTags`) tagged the ALBs and ALB security groups but left the two shared backend groups blank (the controller creates them once and never retags) and let a default `Name` beat the per-ingress `Name`. The second dropped the default `Name` and tagged the backend groups with `aws_ec2_tag`. **Both applied and verified live**: every ALB, target group and security group now has a Name and all five tags. The broader audit then found two more gaps — see AC #14. The audit's two gaps are now closed: the state bucket's tag, and the log groups — which turned out to be **three plus one that did not exist yet**, found by checking the whole class (every service that creates a log group implicitly) rather than the two I had noticed |
| 7 | The first run of the AWS access check (after merge to `dev`) | The CI role **could not be assumed by any workflow**: `Not authorized to perform sts:AssumeRoleWithWebIdentity`, 14 retries. This repository issues **immutable OIDC subject claims** — the subject embeds the numeric owner and repository ids — so a role trusting `repo:Oteemo/backstage-app:…` never matches. CloudTrail recorded the exact subject GitHub sent. It was merged anyway: 18 green checks, a self-review, and tests that asserted the classic form against the classic form, so every test passed on a role nothing could assume. I had also told you the role was "wired" | `subject_prefix` input, correct immutable default, tests pinning the **literal strings from CloudTrail** (mutation-checked: they fail on the old prefix). **Applied; the role is now assumed.** The *second* run then failed on my own check — it called `ecr:DescribeRepositories`, which the role intentionally lacks and Dhanush's pipeline never needs. Role right, check wrong; check corrected rather than widening the role. **Third run, from `dev`, passed**: role assumed, deploy rights confirmed, five denials confirmed |

**What happened with item 4, in full, because the order matters.** The docs
first said the ALB "provisions and returns 503" — an assumption. I then
"corrected" that to the opposite, again without testing, rewrote the docs, and
shipped a flag to match. Only afterwards did I test it: an internal-only
probe Ingress with a nonexistent backend got an ALB in ~10 seconds. So the
original statement was right and the "correction" was the error. The probe
resources were deleted and confirmed gone. The lesson is the one this file
exists for: do not turn an assumption into a documented fact in either direction
— test the cheap thing first.

**Defect 2 and defect 3 are the same lesson as the Terraform-provider split:**
anything that depends on a live cluster's state needs an explicit ordering or a
separate apply; Terraform's dependency graph only knows what it is told.

### What the live checks showed

`scripts/verify.sh` ran twice. First: **10 passed, 1 failed, 1 skipped** — the
failure was the Argo UI being internet-facing with no login, a correct failure.
After restricting `argo_inbound_cidrs` (an `omf-dev` apply, then a one-resource
update to the ingress annotation) the ALB's security group went from
`0.0.0.0/0` to a single `/32`, and the second run was **13 passed, 0 failed,
1 skipped**. The skip is the Backstage ingress, deferred by design.

Restricting it means teammates cannot reach the UI until their CIDRs are added
to `argo_inbound_cidrs`.

One claim was wrong and is corrected here: an earlier note said `verify.sh`
could never check the ingress criteria because it read the wrong outputs. It
reads the right ones. The real gap was that it never checked Argo's ALB at
all; it now does, for both HTTPS and the redirect.

---

## Cross-ticket check — 29 October

Read issues #1–#4 against what #5 delivers, looking for places where someone
else would have been blocked. Five gaps; four were ours to fix, one is
informational.

| Ticket | Gap | Fix |
|---|---|---|
| **#4** (Dhanush) | Its deploy job uses a GitHub Environment named `dev`. A job that declares an environment presents the OIDC subject `environment:dev`, **not** `ref:refs/heads/dev`. Our role trusted branches only, so the deploy would have **failed at AssumeRoleWithWebIdentity**. The module supported environments; the root never passed them | `github_allowed_environments` (default `["dev"]`) wired through. Exact match, still `StringEquals`, no wildcards. Test added on the subjects the role actually trusts |
| **#2** (Nikhil) | Okta needs the Backstage URL before deployment; the Backstage ALB did not exist (see item 4 above) | Ingress back on by default |
| **#2, #3, #4** | The `github-token`, `okta-client-secret` and `backend-secret` containers existed but were **empty and never projected into the cluster** — only the database secret was. Nobody could have consumed them even after setting a value | One `ExternalSecret` each, delivering `GITHUB_TOKEN`, `OKTA_CLIENT_SECRET`, `BACKEND_SECRET`. Separate objects so each works as soon as its own value is set |
| **#1** | Backstage reaches Argo through the public ALB, leaving the VPC via the NAT gateway. Restricting the Argo UI to one address would **block Backstage from Argo** | NAT address added to the allowlist automatically when a restriction is set. Test added, plus one proving "unrestricted" stays visibly unrestricted |
| **#1** | Argo runs with no login but #1 asks for a least-privilege token; the workflow IAM role is artifact-bucket-only but #1 needs CodeArtifact and IAM | **Not changed** — both are decisions for #1, not drop-in fixes. Recorded in the README |

Also checked and fine: cluster access. The admin entry is keyed on the
**AdministratorAccess permission-set role**, so any teammate assigned that
permission set in the sandbox already has `kubectl`. `PowerUserAccess` does not.

**A test that passed in CI and would have failed on a laptop.** While adding the
tests, one failed locally and not in CI: `terraform test` also reads a local
`terraform.tfvars`, so a test relying on a variable's default saw my real
values. The code was right and the test was environment-dependent. Pinned the
input, and re-ran with the file moved aside to prove it holds both ways.

The full contract for each ticket — what exists, what to name things, who fills
which secret — is in the README under "What the other tickets can rely on".

---

## First deploy — 2 Nov

Issue #4's pipeline (Dhanush's PR #6, plus our IRSA change) deployed Backstage for the first
time. What the run showed, each read from the run log or checked on the live system:

| | |
|---|---|
| Image | Built in about 5 min, 171 MB, scanned clean, pushed to ECR as `:<commit-sha>` and `:dev` (confirmed in the registry) |
| Identity | CI role assumed through the `dev` Environment — the path proven earlier on 30 Oct |
| Deploy | Helm install took 35 s with `--wait`; pod `Running`, ready, **0 restarts**; ALB target `healthy` |
| Smoke test | `Health: ok` and `GET /api/catalog/entities → 200` using the backend token, which also proves the CI role can read that Secret |
| Auth | The same catalog call with **no** token returns 401 |
| ServiceAccount | Now Helm-owned and carrying the IRSA annotation |
| Logs | Three harmless warnings (no events backend, no Kubernetes plugin config, empty TechDocs index); no errors |

**Caught before it ran, so it did not fail the first deploy:**

- **A leftover ServiceAccount.** `verify.sh` had created the real `backstage` ServiceAccount on
  29 Oct and never removed it; Helm refuses to adopt a resource it did not create. A server-side
  Helm dry run against the live cluster reproduced the error. Fixed (PR #22) and the leftover
  removed.
- **A missing IRSA role.** The chart only annotates the ServiceAccount when told the role, and
  the deploy step never told it. Found in review; passed from a repository variable (PR #23).
- **A formatting failure.** My own new table row failed the repo's Prettier check on the merge,
  so CI stopped it before it reached `dev`. Re-formatted with the repo's option values.

**Second deploy and rollback drill — 2 Nov (all passed):** PR #33 (branding) deployed over the first
release through the same pipeline. A manual run with `image_tag` set to the first release's commit
rolled the live portal back (image and page title both read back), and a second manual run rolled
forward again. Details in `deploy/pipeline.md`.

**Not tested, and the record says so:** the *automatic* rollback on a failed deploy (the smoke test
never failed, so it never ran), and anything about the Guest exposure beyond the 401. (The app using its IRSA
role was not tested on 2 Nov; the TechDocs fix below now shows it reading the bucket.)

**TechDocs — 4 Nov.** The Docs page showed `Building a newer version of this
documentation failed … 403 Forbidden`, then a 404. Cause: the portal built docs inside
its pod and called GitHub's commit-status endpoint, which needs "Commit statuses:
Read-only"; the portal's read-only token holds only Contents and Metadata. Widening the
token would not have been enough, because the pod has no docs tool. Fix: build in CI
instead (PR #44: CI role may read, write and delete objects in the TechDocs bucket only;
PR #45: `TechDocs publish` workflow, `techdocs.builder: external`, `awsS3` publisher).
Evidence read from the live system: 55 objects published for `backstage-app`; the docs
metadata and index endpoints return 200 for a Guest; the portal's sync step now returns
200; the Docs page renders in the browser. **Not tested:** a second publish after a docs
change, and any entity other than `backstage-app` (only it has a `techdocs-ref`).

---

## Known gaps

**Backstage is deployed — and open to the internet.** Issue #4's pipeline deployed it on
2 Nov (PR #6). Guest sign-in did **not** work at first: the provider refuses to run outside
development, so the browser got no token and the catalog showed "Could not fetch catalog
entities" (caught from a screenshot, not by a test). PR #37 set
`dangerouslyAllowOutsideDevelopment: true` by decision, so now anyone who finds the URL can
sign in as Guest. **Okta sign-in landed on 9 Nov (PR #9)**, so Guest can now be retired; it is
still on until that is decided. The catalog API still refuses calls without a token (401). The
data is sample data only, but it is a decision to leave it open, not a default to forget.

**The Argo UI is token-only, and still internet-reachable.** Since 10 Nov it accepts a Bearer
token only; the earlier no-token mode was removed because it could create a WorkflowTemplate
running as the golden-path provisioner ServiceAccount (found by testing: the controller
restriction does not stop a submitter choosing the ServiceAccount). The page is still served to
anyone who can reach it, so `argo_inbound_cidrs` still applies. It is locked to a single address
(plus the NAT), so teammates cannot reach it until their CIDRs are added.

**No node autoscaling.** Node groups are fixed at `max_size = 4` with no
Cluster Autoscaler or Karpenter. The issue asks for "autoscaling up for
workflow bursts" — that is not delivered. A burst of Argo workflows will leave
pods Pending rather than growing the group. Worth deciding whether it belongs
here or in a follow-up.

**CloudWatch log groups — fixed and applied.** EKS and RDS create their log groups
implicitly, so Terraform never tagged them, set a retention (they kept logs forever, so
cost grew quietly) or deleted them on `destroy`. There were three, plus an RDS `upgrade`
group that does not exist until the first upgrade runs and would have leaked later. The
`eks-cluster` and `rds-postgres` modules now create all four first, with tags and a
30-day retention, so they are removed on `destroy` too. This environment already had
three of them, so a one-time `adopt_existing_log_groups = true` imported them (3 imported,
1 added, 3 changed, 0 destroyed); leave it false on a fresh account, where importing
something that does not exist is an error. Verified in AWS afterwards, and a fresh plan
shows no changes. AC #16 (`destroy`) has still not been run.

---

## Decisions made, and why

| Decision | Reasoning |
|---|---|
| S3 native locking, not a DynamoDB table | Issue permits either; one less resource to create, pay for and clean up |
| One VPC shared by both clusters | The Scaffolder must reach the Argo server; peering for a demo is needless work. Clusters stay separate |
| Single NAT gateway | ~$33/month versus triple that. Documented trade-off: if its AZ fails, private subnets lose outbound |
| EKS API access entries, not `aws-auth` | The ConfigMap is edited by hand and drifts out of Terraform's view |
| Secrets created empty | Values set out of band so they never enter code, state or a plan file |
| `recovery_window_in_days = 0` on secrets | The 7–30 day default makes destroy/apply cycles fail on the name still being held, breaking AC #16 |
| Wildcard cert, no apex SAN | One validation record instead of a `for_each` over plan-unknown keys. See below |
| `StringEquals` on the OIDC sub claim | A wildcard would let a fork's PR assume a role that can push images and deploy |
| Account guard in the root module | The hazard with admin credentials is a stale `AWS_PROFILE`, not missing permission |
| **Option B — no domain** (28 Oct) | Decided. Self-signed certificate on the ALB hostname. Consequences are now live, not hypothetical — see below |
| Workloads in a second root module | Terraform cannot reliably configure a provider from values created in the same apply. The `helm` provider needs the cluster endpoint and token, unknown until EKS exists. Splitting removes the problem rather than working around it |
| **Okta deferred; Guest sign-in enabled in production** (2 Nov) | Decided for the demo, as option 1 of three (the others: no browser access, or Guest plus an inbound IP allowlist on the load balancer, the safer follow-up). The portal is reachable from the internet with Guest access, via `dangerouslyAllowOutsideDevelopment` (PR #37); acceptable for a short-lived POC with no real data. **Update 9 Nov:** Okta is live and verified, so Guest is the only open door left; retiring it is pending a decision. Revisit before anything beyond the demo |
| **Argo: token login only, templates only** (10 Nov) | The golden-path workflow runs with an IAM role and later a GitHub App key. Tested after apply: the controller's `workflowRestrictions: Secure` does not stop a submitter choosing the ServiceAccount, and the no-token mode could create a WorkflowTemplate. So the no-token mode was removed (#59). Backstage's token can read one template and run workflows in `argo`; it cannot create templates (403, checked). The UI now asks for a token |
| **Provisioning role scoped by name and a permission boundary** (10 Nov) | The workflow creates IAM roles, and a role that can create roles can grant itself anything. It may create only `gp-*` roles and CodeArtifact resources, each role must carry a boundary that allows CodeArtifact publish only, the boundary cannot be removed, and managed-policy attachment and `PassRole` are denied (#58). Named people can get the same scope through a developer role |
| `client` + `environment` compose the prefix | Reuse: a second client is a new `envs/` directory and different tfvars, no module changes |

---

## Defects the gates caught

All found before any apply. None would have failed `terraform validate`.

| | Found by | Issue |
|---|---|---|
| 1 | tflint | `tls` provider used but never declared in `required_providers` |
| 2 | terraform test | Private subnets relied on the AWS default for `map_public_ip_on_launch` rather than setting it |
| 3 | terraform test | A missing JSON mock made the OIDC tests fail before any assertion ran — they were silently testing nothing |
| 4 | tflint | Two data sources declared and never used |
| 5 | terraform test | ACM certificate carried an apex SAN, forcing `for_each` over `domain_validation_options` — keys unknown at plan time, a known cause of "Invalid for_each argument" on first apply |
| 6 | terraform test | RDS took security groups as a list and did `for_each` over it. IDs come from the EKS cluster in the same apply, so **the first real `plan` would have failed** — AC #2 |

Items 5 and 6 are the same class of bug and would both have surfaced during an
apply.

**Found by testing after apply, 10 Nov (golden-path lockdown, #58 then #59).** Three tests were
run as an administrator. An inline workflow was rejected. A workflow that referenced a template
ran and succeeded. A workflow that referenced a template *and* named the provisioning
ServiceAccount was **not** rejected: it started as that ServiceAccount (it only failed later for
lack of Kubernetes permissions). A separate check from inside the Backstage cluster showed that a
request with no token could create a WorkflowTemplate (HTTP 200), while Backstage's token got 403.
Together they meant an unauthenticated caller could run code as the provisioning role. Fix: the
no-token mode was removed (#59). After the fix: no-token create 401, bad token 401, Backstage
token lists workflows 200, reads its template (404 until applied), other template and create
template 403.

---

## Next

1. ~~README with cost estimate~~ — written
2. ~~Open the PR~~ — PR #7
3. ~~Address the 29 October review~~ — `f10abde`
4. ~~Bootstrap, plan, apply both layers, run `verify.sh`~~ — done 29 Oct
5. ~~Restrict the Argo UI and re-run `verify.sh`~~ — 13 passed, 0 failed, 1 skipped
6. ~~Test RDS reachability from a pod~~ — port open from the Backstage cluster
7. ~~Apply the cross-ticket fixes~~ — **done 29 Oct**, `verify.sh` 15 passed / 0 failed / 0 skipped. Was: **Apply the cross-ticket fixes** — `envs/omf-dev` first (CI role trust and Argo allowlist; one in-place IAM change), then `envs/omf-dev-workloads` (creates the Backstage ALB, projects the three secrets). Until applied, none of the cross-ticket section is live
8. ~~Wire the GitHub Actions role~~ — **done 29 Oct**; the access check passes from `dev`, and since 30 Oct also through the `environment:dev` identity
9. ~~Create the GitHub Environment `dev`, limited to the `dev` branch~~ — **done 30 Oct** once the engineer was made a repo admin (an engineer on `write` gets a plain 404, which reads as a missing endpoint rather than a missing permission). Read back from GitHub: custom branch policy, only `dev`. Still unproven: that another branch is actually refused
10. ~~Issue #4 deploys Backstage~~ — **done 2 Nov**: PR #6 merged, the pipeline ran end to end and the smoke test returned 200. The rollback drill passed on 2 Nov; Okta is live (9 Nov).
11. ~~Okta secrets, Argo token login and the TechDocs publishing path~~ — **done 4–9 Nov** (PRs #44, #45, #9, #52, #53)
12. ~~Scoped AWS access for the provisioning workflow and the Argo lockdown~~ — **done 10 Nov** (PRs #58, #59), tested after apply; stub `WorkflowTemplate` applied and run through the real Argo on 12 Nov (Scaffolder side, #55)
13. **`terraform destroy`**, workloads first — AC #16. **Not before** the ECR repository has served its purpose: destroy deletes it and its images, and another ticket depends on it

## Open questions

- **When does this come down?** It is running at ~$377/month. Apply → verify →
  destroy is the intended pattern, but the ECR repository is now a dependency of
  another ticket, so teardown needs to be coordinated rather than automatic.
- **Does node autoscaling belong in this issue or a follow-up?** The issue text
  asks for it; nothing here delivers it. See gaps.
- ~~Ordering with issue #2 (Okta).~~ Resolved: the redirect URI was registered after the
  load balancer existed, and Okta sign-in works. The hostname still changes if the stack is
  rebuilt, so the Okta app would need updating then.
- **Retire Guest sign-in?** Okta is live. Retiring Guest locks out anyone without an Okta
  user, so check who needs access first.

---

## Cost estimate

Matches `infra/README.md` — that file is the one to edit if these change.

| Item | ~$/month |
|---|---|
| 2 × EKS control plane @ $0.10/hr | 146 |
| 3 × nodes (2 × t3.large, 1 × t3.medium) | 152 |
| NAT gateway, single | 33 + data |
| RDS `db.t4g.micro`, single-AZ, 20 GB | 13 |
| 2 × ALB | 33 |
| S3, ECR, Secrets Manager | < 5 |
| **Total** | **~377** |

**Roughly $12/day.** The earlier figure of ~$315 understated the nodes by $62
and omitted S3, ECR and Secrets Manager; it was corrected after the 29 October
review.

The two control planes are a third of the bill and are unavoidable — the issue
mandates separate clusters. This assumes a Kubernetes version in EKS **standard
support**; extended support is billed at roughly $0.60 per cluster-hour against
$0.10, which would take the control planes from ~$146 to ~$870 a month. The
`kubernetes_version` variable rejects known extended-support versions for that
reason.

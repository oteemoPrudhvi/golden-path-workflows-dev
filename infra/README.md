# infra — per-package Terraform

Applied by the Argo workflow (`argo/workflow-template.yaml`, stage 3) once per
generated Python package. It creates:

- a CodeArtifact repository named after the package, in the shared domain
- (optionally) a GitHub OIDC publish role `gp-<package>`, trusted only from
  version tags and the default branch — never pull requests

The shared domain is **not** created here; it comes from
[`../infra-prerequisites`](../infra-prerequisites/README.md), which must be
applied first.

## Layout

```
infra/
  backend.tf               partial S3 backend; the workflow supplies bucket/region/key
  versions.tf              terraform + provider constraints
  main.tf                  provider, locals, modules
  variables.tf  outputs.tf
  terraform.tfvars.example local-run example
  backend.hcl.example      local-run example
  modules/
    codeartifact-repository/
    github-oidc-publish-role/
  tests/                   plan-level tests (no AWS credentials needed)
```

One state file per package: `golden-path/packages/<package_name>/terraform.tfstate`.

## Test

```bash
terraform init -backend=false
terraform validate
terraform test                       # root module
(cd modules/<name> && terraform init -backend=false && terraform test)
```

## Run locally

```bash
export AWS_PROFILE=golden-path
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl \
  -backend-config="key=golden-path/packages/<package_name>/terraform.tfstate"
terraform plan
```

`.terraform.lock.hcl` is committed on purpose: it pins the exact provider build.

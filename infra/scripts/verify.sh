#!/usr/bin/env bash
# =============================================================================
# Post-apply verification for issue #5
# =============================================================================
# Checks the acceptance criteria that can only be confirmed against a running
# environment. Read-only apart from one throwaway pod and one test workflow,
# both cleaned up.
#
#   ./scripts/verify.sh [path-to-env]     default: envs/omf-dev
#
# Requires: terraform, aws, kubectl. Exits non-zero if any check fails.
# =============================================================================
set -uo pipefail

ENV_DIR="${1:-envs/omf-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

PASS=0; FAIL=0; SKIP=0

ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[33mSKIP\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; SKIP=$((SKIP+1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1"; exit 2; }; }
need terraform; need aws; need kubectl

section "Reading Terraform outputs from $ENV_DIR"
if ! TF_JSON=$(terraform -chdir="$ENV_DIR" output -json 2>/dev/null); then
  echo "  Could not read outputs. Has '$ENV_DIR' been applied?"
  exit 2
fi
tfout() { echo "$TF_JSON" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('$1',{}).get('value') or '')" 2>/dev/null; }

REGION=$(tfout region)
BACKSTAGE_CLUSTER=$(tfout backstage_cluster_name)
ARGO_CLUSTER=$(tfout argo_cluster_name)
TECHDOCS_BUCKET=$(tfout techdocs_bucket)
ARTIFACTS_BUCKET=$(tfout argo_artifacts_bucket)
DB_ENDPOINT=$(tfout database_endpoint)
IRSA_ROLE=$(echo "$TF_JSON" | python3 -c "
import sys,json;d=json.load(sys.stdin)
v=d.get('backstage_service_account_annotation',{}).get('value','')
print(v.split(': ',1)[1] if ': ' in v else '')" 2>/dev/null)

echo "  region=$REGION  backstage=$BACKSTAGE_CLUSTER  argo=$ARGO_CLUSTER"

# --- AC #3: both clusters ACTIVE, nodes Ready --------------------------------
section "AC #3 — clusters ACTIVE, nodes Ready"
for C in "$BACKSTAGE_CLUSTER" "$ARGO_CLUSTER"; do
  ST=$(aws eks describe-cluster --name "$C" --region "$REGION" --query 'cluster.status' --output text 2>/dev/null)
  [ "$ST" = "ACTIVE" ] && ok "$C is ACTIVE" || bad "$C status is '${ST:-unreachable}'"

  aws eks update-kubeconfig --name "$C" --region "$REGION" >/dev/null 2>&1
  NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -cv ' Ready ' || true)
  TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "${TOTAL:-0}" -gt 0 ] && [ "${NOT_READY:-1}" -eq 0 ]; then
    ok "$C — all $TOTAL node(s) Ready"
  else
    bad "$C — $NOT_READY of ${TOTAL:-0} node(s) not Ready"
  fi
done

# --- AC #5: RDS not reachable from the internet ------------------------------
section "AC #5 — RDS private"
DB_ID=$(aws rds describe-db-instances --region "$REGION" \
  --query "DBInstances[?Endpoint.Address=='${DB_ENDPOINT%%:*}'].DBInstanceIdentifier | [0]" --output text 2>/dev/null)
if [ -n "$DB_ID" ] && [ "$DB_ID" != "None" ]; then
  PUB=$(aws rds describe-db-instances --db-instance-identifier "$DB_ID" --region "$REGION" \
    --query 'DBInstances[0].PubliclyAccessible' --output text 2>/dev/null)
  [ "$PUB" = "False" ] && ok "RDS is not publicly accessible" || bad "RDS PubliclyAccessible=$PUB"

  # Belt and braces: the subnets it sits in must have no route to an IGW.
  SUBNETS=$(aws rds describe-db-instances --db-instance-identifier "$DB_ID" --region "$REGION" \
    --query 'DBInstances[0].DBSubnetGroup.Subnets[].SubnetIdentifier' --output text 2>/dev/null)
  PUBLIC_FOUND=0
  for S in $SUBNETS; do
    RT=$(aws ec2 describe-route-tables --region "$REGION" \
      --filters "Name=association.subnet-id,Values=$S" \
      --query 'RouteTables[].Routes[?GatewayId!=`null`].GatewayId' --output text 2>/dev/null)
    echo "$RT" | grep -q 'igw-' && PUBLIC_FOUND=1
  done
  [ "$PUBLIC_FOUND" -eq 0 ] && ok "RDS subnets have no internet gateway route" \
                            || bad "An RDS subnet routes to an internet gateway"
else
  bad "Could not locate the RDS instance"
fi

# --- AC #10: IRSA to the TechDocs bucket, no static keys ---------------------
section "AC #10 — TechDocs bucket via IRSA"
aws eks update-kubeconfig --name "$BACKSTAGE_CLUSTER" --region "$REGION" >/dev/null 2>&1
if [ -z "$IRSA_ROLE" ] || [ -z "$TECHDOCS_BUCKET" ]; then
  skip "IRSA test" "missing role arn or bucket name in outputs"
else
  # The role trusts system:serviceaccount:<backstage-ns>:<backstage-sa> and
  # nothing else, so the test pod must run as exactly that. An earlier version
  # used a throwaway namespace and failed by design — caught in review.
  SA_NS=$(tfout backstage_namespace); SA_NS=${SA_NS:-backstage}
  SA_NAME="backstage"

  kubectl create namespace "$SA_NS" 2>/dev/null || true

  # Create the ServiceAccount only if it is absent, and remember that we did.
  # The test has to run as the real `backstage` account (that is all the role trusts), which
  # is also the name the Helm chart owns. An earlier version created it, annotated it with
  # --overwrite and left it behind: Helm refuses to adopt a ServiceAccount it did not create
  # ("exists and cannot be imported into the current release"), so the first deploy would have
  # failed, and a later run would have rewritten the annotation on Helm's own object. Found
  # by a server-side Helm dry run before the first deploy.
  CREATED_SA=0
  if ! kubectl -n "$SA_NS" get serviceaccount "$SA_NAME" >/dev/null 2>&1; then
    kubectl -n "$SA_NS" create serviceaccount "$SA_NAME" >/dev/null && CREATED_SA=1
    kubectl -n "$SA_NS" annotate serviceaccount "$SA_NAME" \
      "eks.amazonaws.com/role-arn=$IRSA_ROLE" >/dev/null
  fi

  # -i is required: without it --attach never delivers stdin and the upload
  # hangs rather than writing. Stderr is captured, not discarded, so a
  # failure says why.
  if OUT=$(echo verify | kubectl -n "$SA_NS" run "irsa-check-$$" \
      --rm -i --restart=Never --quiet \
      --image=amazon/aws-cli:latest \
      --overrides="{\"spec\":{\"serviceAccountName\":\"$SA_NAME\"}}" \
      -- s3 cp - "s3://$TECHDOCS_BUCKET/.verify-$$" 2>&1); then
    ok "pod wrote to s3://$TECHDOCS_BUCKET using IRSA"
    aws s3 rm "s3://$TECHDOCS_BUCKET/.verify-$$" --region "$REGION" >/dev/null 2>&1
  else
    bad "pod could not write to the TechDocs bucket" "$(echo "$OUT" | tail -2 | tr '\n' ' ')"
  fi

  # Remove only what this script created, so it never blocks a later Helm install.
  if [ "$CREATED_SA" = 1 ]; then
    kubectl -n "$SA_NS" delete serviceaccount "$SA_NAME" >/dev/null 2>&1
  fi
fi

# --- AC #9: hello-world workflow, artifact in S3 -----------------------------
section "AC #9 — Argo hello-world workflow"
aws eks update-kubeconfig --name "$ARGO_CLUSTER" --region "$REGION" >/dev/null 2>&1
if ! kubectl get ns argo >/dev/null 2>&1; then
  skip "workflow test" "argo namespace not found — has envs/omf-dev-workloads been applied?"
else
  WF="verify-hello-$$"
  # The controller only accepts workflows that reference a WorkflowTemplate
  # (workflowRestrictions: Secure, set by envs/omf-dev-workloads), so an inline
  # Workflow would be rejected. Create a throwaway template and run from it.
  cat <<YAML | kubectl -n argo apply -f - >/dev/null 2>&1
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: $WF
spec:
  # Created and IRSA-annotated by envs/omf-dev-workloads. Workflow pods
  # need the artifact role or the run succeeds and stores nothing.
  serviceAccountName: argo-workflow
  entrypoint: hello
  templates:
    - name: hello
      container:
        image: busybox
        command: [sh, -c]
        args: ["echo hello world | tee /tmp/out.txt"]
      outputs:
        artifacts:
          - name: result
            path: /tmp/out.txt
---
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: $WF
spec:
  workflowTemplateRef:
    name: $WF
YAML
  for _ in $(seq 1 60); do
    PH=$(kubectl -n argo get workflow "$WF" -o jsonpath='{.status.phase}' 2>/dev/null)
    [ "$PH" = "Succeeded" ] || [ "$PH" = "Failed" ] || [ "$PH" = "Error" ] && break
    sleep 5
  done
  [ "$PH" = "Succeeded" ] && ok "workflow reached Succeeded" || bad "workflow phase is '${PH:-unknown}'"

  if [ -n "$ARTIFACTS_BUCKET" ]; then
    sleep 5
    N=$(aws s3 ls "s3://$ARTIFACTS_BUCKET/" --recursive --region "$REGION" 2>/dev/null | grep -c "$WF" || true)
    [ "${N:-0}" -gt 0 ] && ok "artifact stored in s3://$ARTIFACTS_BUCKET" \
                        || bad "no artifact found for $WF" "controller and workflow pods both need IRSA"
  fi
  kubectl -n argo delete workflow "$WF" >/dev/null 2>&1
  kubectl -n argo delete workflowtemplate "$WF" >/dev/null 2>&1
fi

# --- AC #6/#7/#8: ALB exists, HTTPS serves, HTTP redirects -------------------
section "AC #6/#7/#8 — ingress over HTTPS"
WL_DIR="${ENV_DIR}-workloads"
if [ -d "$WL_DIR" ] && WL_JSON=$(terraform -chdir="$WL_DIR" output -json 2>/dev/null); then
  wlout() { echo "$WL_JSON" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('$1',{}).get('value') or '')" 2>/dev/null; }
  TLS_FLAG=$(tfout smoke_test_tls_flag)

  # HTTPS must answer and plain HTTP must redirect to it. Run per app so a
  # failure names the one that broke.
  # $3 = "backend-pending" accepts a 503 as "ALB up, no ready pods yet". Only
  # Backstage gets this, and only until issue #4 deploys it: for Argo a 503 means
  # something is genuinely wrong.
  check_ingress() {
    local label="$1" url="$2" mode="${3:-}"
    # shellcheck disable=SC2086
    CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 $TLS_FLAG "$url" 2>/dev/null)
    case "$CODE" in
      200|302|303|401|403|404) ok "$label: HTTPS reachable at $url (HTTP $CODE)" ;;
      503)
        if [ "$mode" = "backend-pending" ]; then
          ok "$label: ALB serving over HTTPS, no ready pods behind it yet (HTTP 503) — expected until issue #4 deploys it"
        else
          bad "$label: HTTPS reachable but the backend is unhealthy" "got 503 from $url"
        fi ;;
      *) bad "$label: HTTPS not reachable at $url" "got '$CODE'" ;;
    esac

    # AC #8: plain HTTP must redirect to HTTPS.
    RCODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "http://${url#https://}" 2>/dev/null)
    case "$RCODE" in
      301|302|307|308) ok "$label: HTTP redirects to HTTPS (HTTP $RCODE)" ;;
      *) bad "$label: HTTP did not redirect" "got '$RCODE'" ;;
    esac
  }

  # Argo's Service comes from its own Helm release, so its ALB always exists
  # and proves the controller, certificate and redirect end to end.
  ARGO_URL=$(wlout argo_url)
  if [ -n "$ARGO_URL" ]; then
    check_ingress "Argo" "$ARGO_URL"
  else
    skip "Argo ingress checks" "no argo_url output — were ingresses created?"
  fi

  # The Backstage ALB exists as soon as its Ingress does — the controller does
  # not wait for the Service (probed 29 Oct 2026). It answers 503 until issue #4
  # deploys pods behind it, so that is accepted here and nowhere else.
  BS_URL=$(wlout backstage_url)
  if [ -n "$BS_URL" ]; then
    check_ingress "Backstage" "$BS_URL" backend-pending
  else
    skip "Backstage ingress checks" "no backstage_url output — create_backstage_ingress is false, or workloads not applied"
  fi

  if [ "$(wlout argo_ui_is_unrestricted)" = "True" ]; then
    bad "Argo UI is internet-facing with no login" "set argo_inbound_cidrs"
  else
    ok "Argo UI is CIDR-restricted"
  fi
else
  skip "ingress checks" "$WL_DIR not applied"
fi

# --- AC #14: tags -------------------------------------------------------------
section "AC #14 — consistent tags"
MISSING=0
for C in "$BACKSTAGE_CLUSTER" "$ARGO_CLUSTER"; do
  TAGS=$(aws eks describe-cluster --name "$C" --region "$REGION" --query 'cluster.tags' --output json 2>/dev/null)
  for K in project environment owner managed-by; do
    echo "$TAGS" | grep -q "\"$K\"" || { bad "$C missing tag '$K'"; MISSING=1; }
  done
done
[ "$MISSING" -eq 0 ] && ok "clusters carry project, environment, owner, managed-by"

# The ALBs, target groups and security groups are created by the load balancer
# controller, not Terraform, so provider default_tags never reach them — they are
# tagged only if the controller is told to. Checking the ALBs, target groups and
# security groups themselves,
# found by the tag the controller always puts on what it creates. The cluster
# check above says nothing about them.
for C in "$BACKSTAGE_CLUSTER" "$ARGO_CLUSTER"; do
  RES=$(aws resourcegroupstaggingapi get-resources --region "$REGION" \
    --tag-filters "Key=elbv2.k8s.aws/cluster,Values=$C" --output json 2>/dev/null)
  RESULT=$(echo "$RES" | python3 -c "
import sys,json
need=['Name','project','environment','owner','managed-by']
# Listeners and listener rules are sub-objects of the ALB. Excluded on purpose,
# and decided before seeing what the controller does with them; widen this if it
# turns out to tag them too.
wanted=('loadbalancer/','targetgroup/','security-group/')
items=[r for r in json.load(sys.stdin).get('ResourceTagMappingList',[])
       if any(w in r['ResourceARN'] for w in wanted)]
if not items:
    print('NONE'); sys.exit()
bad=[]
for r in items:
    t={x['Key'] for x in r['Tags']}
    miss=[k for k in need if k not in t]
    if miss:
        kind=r['ResourceARN'].split(':')[2]+'/'+r['ResourceARN'].split(':')[5].split('/')[0]
        bad.append(kind+' missing '+','.join(miss))
print('OK %d'%len(items) if not bad else 'BAD '+'; '.join(bad))
" 2>/dev/null)
  case "$RESULT" in
    OK*)   ok "$C: ${RESULT#OK } controller-created resources carry Name + standard tags" ;;
    NONE)  skip "$C: controller-created tags" "no controller-created resources found (ingresses not created?)" ;;
    *)     bad "$C: controller-created resources are missing tags" "${RESULT#BAD }" ;;
  esac
done

# --- Summary -----------------------------------------------------------------
printf '\n\033[1mSummary\033[0m\n'
printf '  passed %d   failed %d   skipped %d\n\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
  echo "AC #16 (clean destroy) is NOT covered here — run 'terraform destroy' and"
  echo "confirm the account is empty afterwards."
  exit 1
fi
echo "AC #16 (clean destroy) is not covered here — run 'terraform destroy' and"
echo "confirm the account is empty afterwards."

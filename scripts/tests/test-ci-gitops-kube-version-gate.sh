#!/usr/bin/env bash
# `ci-gitops.yml` validates rendered charts with kubeconform but never compared a
# chart's `kubeVersion` constraint with the cluster it deploys to. A chart bump
# that requires a newer Kubernetes than the cluster runs therefore passed every
# gate and only failed once Fleet tried to install it.
#
# The `Check chart kubeVersion` step closes that: with `kube-version` set it
# reads `kubeVersion` from every Fleet bundle under `fleet-paths` — from the
# local Chart.yaml, or via `helm show chart` for a remote one — and lets Helm
# judge the constraint against the cluster version through an empty probe chart.
#
# These assertions run the step body rather than grep its spelling. A fake
# `helm` sits first on PATH: `show chart` logs its arguments and answers from a
# fixture (or fails, standing in for an unreachable registry), every other call
# goes to the real Helm so the constraint check is Helm's own. Without a real
# Helm the test fails instead of skipping, since the probe is the logic under
# test.
#
# Run: scripts/tests/test-ci-gitops-kube-version-gate.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORKFLOW="$REPO/.github/workflows/ci-gitops.yml"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -f "$WORKFLOW" ] || fail "ci-gitops.yml not found at $WORKFLOW"
REAL_HELM="$(command -v helm || true)"
[ -n "$REAL_HELM" ] || fail "helm is required on PATH; the probe chart is judged by real Helm"
command -v python3 >/dev/null 2>&1 || fail "python3 required to parse the workflow YAML"

# --- locate the step's shell body --------------------------------------------

# Same anchoring as test-ci-gitops-oci-skip-notice.sh: step name, then its
# `run: |`, then the next step as the end bound.
STEP_LINE="$(grep -n '^      - name: Check chart kubeVersion$' "$WORKFLOW" | cut -d: -f1 || true)"
[ -n "$STEP_LINE" ] || fail "no 'Check chart kubeVersion' step found"
[ "$(grep -c . <<<"$STEP_LINE")" -eq 1 ] || fail "expected exactly one kubeVersion step"

RUN_OFFSET="$(sed -n "${STEP_LINE},\$p" "$WORKFLOW" | grep -n '^        run: |$' | head -1 | cut -d: -f1 || true)"
[ -n "$RUN_OFFSET" ] || fail "the kubeVersion step has no 'run: |' body"
BODY_START=$((STEP_LINE + RUN_OFFSET))

END_OFFSET="$(sed -n "$((BODY_START + 1)),\$p" "$WORKFLOW" | grep -n '^      - name: \|^      # \|^  [a-z]' | head -1 | cut -d: -f1 || true)"
[ -n "$END_OFFSET" ] || fail "could not find the end of the kubeVersion step's body"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Literal block at ten spaces; strip it so bash sees the script the runner runs.
sed -n "${BODY_START},$((BODY_START + END_OFFSET - 1))p" "$WORKFLOW" | sed 's/^          //' >"$WORK/step.sh"
# shellcheck disable=SC2016 # the ${{ text is matched literally
grep -q '\${{' "$WORK/step.sh" && fail "the step body interpolates an expression; values must arrive via env:"

# --- fake helm ----------------------------------------------------------------

mkdir -p "$WORK/bin" "$WORK/charts"
cat >"$WORK/bin/helm" <<EOF
#!/usr/bin/env bash
if [ "\$1" = show ] && [ "\$2" = chart ]; then
  printf '%s\n' "\$*" >>"\$HELM_LOG"
  name="\${3##*/}"
  [ -f "$WORK/charts/\$name.yaml" ] || { echo "Error: failed to fetch \$3" >&2; exit 1; }
  cat "$WORK/charts/\$name.yaml"
  exit 0
fi
exec "$REAL_HELM" "\$@"
EOF
chmod +x "$WORK/bin/helm"

cat >"$WORK/charts/deep.yaml" <<'EOF'
apiVersion: v2
name: deep
version: v1.6.0
kubeVersion: ">= 1.34.0-0"
EOF
cat >"$WORK/charts/plainrepo.yaml" <<'EOF'
apiVersion: v2
name: plainrepo
version: 2026.8.5
EOF
cat >"$WORK/charts/garbage.yaml" <<'EOF'
apiVersion: v2
name: garbage
version: 1.0.0
kubeVersion: "not a constraint"
EOF

# run <case> <kube-version>; leaves $OUT, $STATUS, $LOG set. Fixture tree is
# built by the caller under $WORK/<case>.
run() {
  local case="$1"
  LOG="$WORK/$case.log"
  : >"$LOG"
  set +e
  OUT="$(cd "$WORK/$case" && PATH="$WORK/bin:$PATH" HELM_LOG="$LOG" \
    FLEET_PATHS="platform applications" KUBE_VERSION="$2" bash "$WORK/step.sh" 2>&1)"
  STATUS=$?
  set -e
}

bundle() { # bundle <case> <path> <fleet.yaml body>
  mkdir -p "$WORK/$1/$2"
  printf '%s\n' "$3" >"$WORK/$1/$2/fleet.yaml"
}

expect_red() { [ "$STATUS" -ne 0 ] || fail "$1: step passed but must fail"$'\n'"$OUT"; }
expect_green() { [ "$STATUS" -eq 0 ] || fail "$1: step failed but must pass"$'\n'"$OUT"; }
expect_out() { grep -qF -- "$2" <<<"$OUT" || fail "$1: output lacks '$2'"$'\n'"$OUT"; }

OCI_DEEP='defaultNamespace: op
helm:
  chart: "oci://ghcr.io/example/deep"
  version: "v1.6.0"'

# --- nested-oci: bundle two levels deep, constraint too new -> red ------------
bundle nested-oci platform/op/deep "$OCI_DEEP"
mkdir -p "$WORK/nested-oci/applications"
run nested-oci 1.33.3
expect_red nested-oci
expect_out nested-oci '::error::'
expect_out nested-oci 'platform/op/deep'
grep -qF 'show chart oci://ghcr.io/example/deep --version v1.6.0' "$LOG" ||
  fail "nested-oci: helm show chart args wrong (quotes not stripped?): $(cat "$LOG")"

# --- compatible: same bundle, newer cluster -> green --------------------------
bundle compatible platform/op/deep "$OCI_DEEP"
run compatible 1.37.1
expect_green compatible
expect_out compatible 'Checked 1 chart(s), 0 without kubeVersion, 0 unchecked.'

# --- repo-form: repo: + chart:, no kubeVersion --------------------------------
bundle repo-form applications/plainrepo 'helm:
  repo: https://charts.example.com
  chart: plainrepo
  version: 2026.8.5'
run repo-form 1.33.3
expect_green repo-form
expect_out repo-form 'Checked 1 chart(s), 1 without kubeVersion, 0 unchecked.'
grep -qF 'show chart plainrepo --version 2026.8.5 --repo https://charts.example.com' "$LOG" ||
  fail "repo-form: helm show chart args wrong: $(cat "$LOG")"

# --- local: Chart.yaml next to fleet.yaml, never fetched ----------------------
bundle local applications/app 'helm:
  releaseName: app'
printf 'apiVersion: v2\nname: app\nversion: 0.1.0\nkubeVersion: ">=1.34.0-0"\n' >"$WORK/local/applications/app/Chart.yaml"
run local 1.33.3
expect_red local
expect_out local 'applications/app'
[ ! -s "$LOG" ] || fail "local: helm show chart was called for a local chart: $(cat "$LOG")"

# --- unreachable: registry fails -> warning, unchecked, green -----------------
bundle unreachable platform/gone 'helm:
  chart: oci://ghcr.io/example/missing
  version: 1.0.0'
run unreachable 1.33.3
expect_green unreachable
expect_out unreachable '::warning::'
expect_out unreachable 'Checked 0 chart(s), 0 without kubeVersion, 1 unchecked.'

# --- no-version: remote bundle without version: -> warning, green -------------
bundle no-version platform/nover 'helm:
  chart: oci://ghcr.io/example/deep'
run no-version 1.33.3
expect_green no-version
expect_out no-version '::warning::'
expect_out no-version '1 unchecked.'
[ ! -s "$LOG" ] || fail "no-version: helm show chart was called without a version"

# --- unparseable constraint -> red --------------------------------------------
bundle unparseable platform/garbage 'helm:
  chart: oci://ghcr.io/example/garbage
  version: 1.0.0'
run unparseable 1.37.1
expect_red unparseable
expect_out unparseable '::error::'

# --- invalid-input: kube-version is not a version -> red ----------------------
bundle invalid-input platform/op/deep "$OCI_DEEP"
run invalid-input latest
expect_red invalid-input
expect_out invalid-input '::error::'
[ ! -s "$LOG" ] || fail "invalid-input: bundles were checked despite an invalid kube-version"

# --- plain: manifests only, no chart: key -> nothing checked ------------------
bundle plain platform/raw 'defaultNamespace: raw'
run plain 1.33.3
expect_green plain
expect_out plain 'Checked 0 chart(s)'

# --- structure: wiring outside the step body ----------------------------------
# Parsed as YAML so a comment mentioning the ids cannot satisfy the checks.
python3 - "$WORKFLOW" <<'PY' || fail "workflow wiring for kube-version is incomplete"
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
inp = doc[True]["workflow_call"]["inputs"]["kube-version"]
assert inp.get("default") == "" and inp.get("type") == "string", "input kube-version must be a string defaulting to ''"
steps = doc["jobs"]["validate"]["steps"]
by = {s.get("name"): s for s in steps}
gate = by["Check chart kubeVersion"]
assert gate.get("id") == "kube-version", "step id must be kube-version"
assert "inputs.kube-version != ''" in gate.get("if", ""), "step must be gated on a non-empty kube-version"
assert gate.get("continue-on-error") is True, "step must record its outcome, not stop the job"
assert "inputs.kube-version != ''" in by["Set up Helm"].get("if", ""), "Helm must be installed when only the gate is enabled"
for name in ("Validation Summary", "Enforce validation results"):
    assert "steps.kube-version.outcome" in str(by[name].get("env")), f"{name} must read steps.kube-version.outcome"
    assert "Check Chart kubeVersion" in by[name].get("run", ""), f"{name} must name the check"
PY

echo "PASS: ci-gitops.yml gates chart kubeVersion against kube-version"

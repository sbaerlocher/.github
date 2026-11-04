#!/usr/bin/env bash
# The helm lint and render steps in ci-gitops.yml used to walk exactly one level
# below each fleet-paths entry (`for dir in "$base"/*`), while the Fleet step in
# the same file finds fleet.yaml recursively. A bundle one level deeper — e.g.
# `platform/<group>/<bundle>/` — was therefore neither linted nor rendered,
# and a nested remote-chart bundle was missing from the `skipped N` count, so
# the summary line claimed coverage it did not have.
#
# This test runs the real step bodies against a fixture tree with stub `helm`
# and `kubeconform` binaries and pins what each step actually touches:
#   - local charts at any depth are linted and rendered,
#   - nested remote-chart bundles are counted as skipped,
#   - a directory holding both fleet.yaml and Chart.yaml is handled once,
#   - a subchart under `<chart>/charts/` is not linted or rendered on its own
#     (it needs its parent's values and is covered through the parent),
#   - a directory name containing a space survives.
#
# Run: scripts/tests/test-ci-gitops-nested-bundles.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORKFLOW="$REPO/.github/workflows/ci-gitops.yml"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -f "$WORKFLOW" ] || fail "ci-gitops.yml not found at $WORKFLOW"

# Print the `run: |` body of the step named $1, de-indented. Bounded on the
# next step (or job) so a later step cannot leak into the extracted script.
step_body() {
  local start run_off body_start end_off
  start="$(grep -n "^      - name: $1\$" "$WORKFLOW" | cut -d: -f1 || true)"
  [ -n "$start" ] || fail "no '$1' step found"
  [ "$(grep -c . <<<"$start")" -eq 1 ] || fail "expected exactly one '$1' step"
  run_off="$(sed -n "${start},\$p" "$WORKFLOW" | grep -n '^        run: |$' | head -1 | cut -d: -f1 || true)"
  [ -n "$run_off" ] || fail "the '$1' step has no 'run: |' body"
  body_start=$((start + run_off))
  end_off="$(sed -n "${body_start},\$p" "$WORKFLOW" | grep -n '^      - name: \|^  [a-z]' | head -1 | cut -d: -f1 || true)"
  [ -n "$end_off" ] || fail "could not find the end of the '$1' step"
  sed -n "${body_start},$((body_start + end_off - 2))p" "$WORKFLOW" | sed -E 's/^ {10}//'
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- fixture ----------------------------------------------------------------

F="$TMP/fixture"
mkchart() { mkdir -p "$F/$1" && printf 'apiVersion: v2\nname: x\nversion: 0.1.0\n' >"$F/$1/Chart.yaml"; }

mkchart apps/flat
mkchart apps/group/nested
mkchart 'apps/grp two/my chart'
mkchart apps/withsub
mkchart apps/withsub/charts/sub
mkchart apps/bundle
printf 'defaultNamespace: x\n' >"$F/apps/bundle/fleet.yaml"
mkdir -p "$F/apps/group/remote" "$F/apps/flatremote" "$F/apps/plain"
printf 'helm:\n  chart: "oci://registry.example/x"\n  version: 1.0.0\n' >"$F/apps/group/remote/fleet.yaml"
printf 'helm:\n  repo: https://charts.example\n  chart: x\n  version: 1.0.0\n' >"$F/apps/flatremote/fleet.yaml"
printf 'defaultNamespace: x\n' >"$F/apps/plain/fleet.yaml"

# --- stub tools -------------------------------------------------------------

BIN="$TMP/bin"
mkdir -p "$BIN"
cat >"$BIN/helm" <<'EOF'
#!/usr/bin/env bash
printf '%s\t%s\n' "$1" "$2" >>"$HELM_LOG"
EOF
cat >"$BIN/kubeconform" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
EOF
chmod +x "$BIN/helm" "$BIN/kubeconform"

run_step() {
  : >"$TMP/helm.log"
  (cd "$F" && PATH="$BIN:$PATH" HELM_LOG="$TMP/helm.log" FLEET_PATHS=apps STRICT=true \
    bash -eo pipefail <<<"$(step_body "$1")") >"$TMP/out.log" 2>&1 ||
    {
      cat "$TMP/out.log" >&2
      fail "'$1' step exited non-zero"
    }
}

EXPECTED_CHARTS="$(printf '%s\n' apps/bundle apps/flat apps/group/nested 'apps/grp two/my chart' apps/withsub)"

# --- 1. lint step -----------------------------------------------------------

run_step 'Lint Helm Charts'
LINTED="$(awk -F'\t' '$1 == "lint" { print $2 }' "$TMP/helm.log" | sort)"
[ "$LINTED" = "$EXPECTED_CHARTS" ] ||
  fail "lint step touched an unexpected set of charts:
$LINTED
expected:
$EXPECTED_CHARTS"

# --- 2. render step ---------------------------------------------------------

run_step 'Render charts and validate with kubeconform'
RENDERED_DIRS="$(awk -F'\t' '$1 == "template" { print $2 }' "$TMP/helm.log" | sort)"
[ "$RENDERED_DIRS" = "$EXPECTED_CHARTS" ] ||
  fail "render step rendered an unexpected set of charts:
$RENDERED_DIRS
expected:
$EXPECTED_CHARTS"

grep -qx 'Rendered 5 chart(s), skipped 2 bundle(s) with a remote chart reference.' "$TMP/out.log" ||
  fail "render summary does not count nested bundles: $(grep '^Rendered' "$TMP/out.log" || echo '<none>')"

grep -q '^::notice::apps/group/remote references a remote chart' "$TMP/out.log" ||
  fail "no remote-chart notice for the nested bundle apps/group/remote"

echo "PASS: ci-gitops.yml lints and renders Fleet bundles at any depth"

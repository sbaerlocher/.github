#!/usr/bin/env bash
# `validate-helm-template` renders every directory that carries a local
# Chart.yaml and skips the rest. A Fleet bundle that pulls its chart via
# `chart: oci://…` has no local Chart.yaml, so it fell out of the loop with no
# output at all: the job ended green and `Rendered N chart(s)` counted only the
# local charts. A wrong registry path, a chart version that does not exist, or
# invalid values in such a bundle therefore surfaced at Fleet deploy time
# instead of in CI.
#
# The skip itself stays — rendering an OCI chart needs registry auth in the
# runner and an answer for mapping Fleet values onto `helm template` values,
# which is a separate change. What this pins is that the skip is *announced*:
# each skipped OCI bundle gets a `::notice::` and the summary line reports the
# count, so the coverage gap is visible in the log rather than silent.
#
# The assertions are scoped to the render step's body. `chart: oci://` also
# appears in the validate-gitrepo step further up the same file, so a file-wide
# grep would pass on that unrelated occurrence and prove nothing about this
# loop.
#
# Run: scripts/tests/test-ci-gitops-oci-skip-notice.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORKFLOW="$REPO/.github/workflows/ci-gitops.yml"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -f "$WORKFLOW" ] || fail "ci-gitops.yml not found at $WORKFLOW"

# --- locate the render step's shell body -------------------------------------

# Anchored on the step name, then on the `run: |` that follows it, so the `env:`
# block in between cannot satisfy an assertion meant for the shell body.
STEP_LINE="$(grep -n '^      - name: Render charts and validate with kubeconform$' "$WORKFLOW" | cut -d: -f1 || true)"
[ -n "$STEP_LINE" ] || fail "no 'Render charts and validate with kubeconform' step found"
[ "$(grep -c . <<<"$STEP_LINE")" -eq 1 ] || fail "expected exactly one render step"

RUN_OFFSET="$(sed -n "${STEP_LINE},\$p" "$WORKFLOW" | grep -n '^        run: |$' | head -1 | cut -d: -f1 || true)"
[ -n "$RUN_OFFSET" ] || fail "the render step has no 'run: |' body"

BODY_START=$((STEP_LINE + RUN_OFFSET))

# The body ends at the next job (a two-space-indented key), so a step or job
# added after it cannot widen the range and satisfy an assertion from outside
# this loop.
END_OFFSET="$(sed -n "$((BODY_START + 1)),\$p" "$WORKFLOW" | grep -n '^  [a-z]' | head -1 | cut -d: -f1 || true)"
[ -n "$END_OFFSET" ] || fail "could not find the end of the render step's body"

BODY="$(sed -n "${BODY_START},$((BODY_START + END_OFFSET - 1))p" "$WORKFLOW")"

# --- 1. the OCI bundle is detected before the skip ----------------------------

# Without this test the loop cannot tell an OCI bundle apart from a directory
# that is simply not a chart, and every skip would either be silent again or
# announce itself on unrelated directories.
grep -q 'chart: oci://' <<<"$BODY" ||
  fail "the render loop never tests for an OCI chart reference; skipped bundles would be silent again"

grep -q 'fleet\.yaml' <<<"$BODY" ||
  fail "the render loop never reads fleet.yaml; it has no source for the OCI reference"

# --- 2. the skip is announced -------------------------------------------------

# The `::notice::` is the whole point of the change: the behaviour is unchanged,
# only the visibility. Anchored on the annotation prefix plus the render step's
# own wording so it cannot be satisfied by the other notices in this workflow —
# those live in different steps and are outside $BODY anyway.
grep -q '::notice::.*OCI' <<<"$BODY" ||
  fail "no ::notice:: is emitted for a skipped OCI bundle; the coverage gap stays invisible in the log"

# --- 3. the count reaches the summary line ------------------------------------

# `Rendered N chart(s)` alone reads as full coverage. The skip count is what
# tells a reader the number is partial, so both the counter and its use in the
# summary are pinned; dropping either leaves the misleading line behind.
grep -q 'SKIPPED_OCI=0' <<<"$BODY" ||
  fail "SKIPPED_OCI is never initialised; under 'set -u' the increment would abort the step"

# shellcheck disable=SC2016 # the $((…)) text is matched literally in the YAML
grep -q 'SKIPPED_OCI=\$((SKIPPED_OCI + 1))' <<<"$BODY" ||
  fail "SKIPPED_OCI is never incremented; the summary would always report zero skipped bundles"

# shellcheck disable=SC2016 # the $RENDERED/$SKIPPED_OCI text is matched literally in the YAML
grep -q 'echo "Rendered \$RENDERED chart(s), skipped \$SKIPPED_OCI' <<<"$BODY" ||
  fail "the summary line does not report the skipped OCI bundles; 'Rendered N chart(s)' still reads as full coverage"

# --- 4. the skip still happens ------------------------------------------------

# The notice must not turn into a render attempt: `helm template` on a directory
# without a Chart.yaml hard-fails, which would take every OCI bundle red.
grep -q 'continue' <<<"$BODY" ||
  fail "the loop no longer skips directories without a local Chart.yaml"

echo "PASS: ci-gitops.yml announces skipped OCI-referenced bundles"

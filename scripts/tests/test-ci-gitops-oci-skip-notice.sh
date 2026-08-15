#!/usr/bin/env bash
# `validate-helm-template` renders every directory that carries a local
# Chart.yaml and skips the rest. A Fleet bundle that pulls its chart from a
# registry — `chart: oci://…`, or `repo:` + `chart:` against a classic HTTP Helm
# repo — has no local Chart.yaml, so it fell out of the loop with no output at
# all: the job ended green and `Rendered N chart(s)` counted only the local
# charts. A wrong registry path, a chart version that does not exist, or invalid
# values in such a bundle therefore surfaced at Fleet deploy time instead of in
# CI.
#
# The skip itself stays — rendering a remote chart needs registry auth in the
# runner and an answer for mapping Fleet values onto `helm template` values,
# which is a separate change. What this pins is that the skip is *announced*:
# each skipped bundle gets a `::notice::` and the summary line reports the
# count, so the coverage gap is visible in the log rather than silent. A counter
# that only covered part of the remote forms would be worse than none, since
# `skipped 0` then reads as an affirmative claim of full coverage.
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

# The body ends at the next *step* (`- name:` at step indentation), with the
# next job key as the fallback for the case where this is the last step in its
# job. Bounding on the job alone would let every later step in
# `validate-helm-template` fall inside the range, so an assertion below could be
# satisfied by an unrelated step while the render loop had lost the logic
# entirely — the range has to end where the step does, not where the job does.
END_OFFSET="$(sed -n "$((BODY_START + 1)),\$p" "$WORKFLOW" | grep -n '^      - name: \|^  [a-z]' | head -1 | cut -d: -f1 || true)"
[ -n "$END_OFFSET" ] || fail "could not find the end of the render step's body"

BODY="$(sed -n "${BODY_START},$((BODY_START + END_OFFSET - 1))p" "$WORKFLOW")"

# --- 1. the remote-chart bundle is detected before the skip -------------------

# Without this test the loop cannot tell a bundle that fetches its chart from a
# registry apart from a directory that is simply not a chart, and every skip
# would either be silent again or announce itself on unrelated directories.
#
# Matched loosely (`chart:.*oci://`) rather than on a literal `chart: oci://`:
# the pattern in the workflow tolerates quoting and arbitrary whitespace after
# the key, and pinning the literal spelling here would fail the healthy file.
grep -qE 'chart:.*oci://' <<<"$BODY" ||
  fail "the render loop never tests for an OCI chart reference; those bundles would be skipped silently again"

# The other remote form: `repo:` + `chart:` against a classic HTTP Helm repo.
# It has no local Chart.yaml either, so leaving it out would make the summary
# assert coverage it does not have.
grep -qE 'repo:.*https\?://' <<<"$BODY" ||
  fail "the render loop never tests for an HTTP Helm repo reference; those bundles would be skipped silently and uncounted"

grep -q 'fleet\.yaml' <<<"$BODY" ||
  fail "the render loop never reads fleet.yaml; it has no source for the remote chart reference"

# --- 2. the skip is announced, with the newline guard -------------------------

# The `::notice::` is the whole point of the change: the behaviour is unchanged,
# only the visibility.
grep -q '::notice::' <<<"$BODY" ||
  fail "no ::notice:: is emitted for a skipped bundle; the coverage gap stays invisible in the log"

# `$dir` comes from a glob over the checked-out tree and Git permits newlines in
# path names, so an unguarded expansion could smuggle a second workflow command
# into the log. Same guard the validate-gitrepo notice in this file already uses.
# shellcheck disable=SC2016 # the ${dir%%…} text is matched literally in the YAML
grep -q '::notice::\${dir%%\$'"'"'\\n'"'"'\*}' <<<"$BODY" ||
  fail "the notice interpolates \$dir without the first-line-only guard; a newline in a path name could inject a second workflow command"

# --- 3. the count reaches the summary line ------------------------------------

# `Rendered N chart(s)` alone reads as full coverage. The skip count is what
# tells a reader the number is partial, so both the counter and its use in the
# summary are pinned; dropping either leaves the misleading line behind.
grep -q 'SKIPPED_REMOTE=0' <<<"$BODY" ||
  fail "SKIPPED_REMOTE is never initialised; under 'set -u' the increment would abort the step"

# shellcheck disable=SC2016 # the $((…)) text is matched literally in the YAML
grep -q 'SKIPPED_REMOTE=\$((SKIPPED_REMOTE + 1))' <<<"$BODY" ||
  fail "SKIPPED_REMOTE is never incremented; the summary would always report zero skipped bundles"

# shellcheck disable=SC2016 # the $RENDERED/$SKIPPED_REMOTE text is matched literally in the YAML
grep -q 'echo "Rendered \$RENDERED chart(s), skipped \$SKIPPED_REMOTE' <<<"$BODY" ||
  fail "the summary line does not report the skipped bundles; 'Rendered N chart(s)' still reads as full coverage"

# --- 4. the skip still happens ------------------------------------------------

# The notice must not turn into a render attempt: `helm template` on a directory
# without a Chart.yaml hard-fails, which would take every remote bundle red.
#
# Anchored on the guard *and* on the `continue` at the guard's own indentation.
# An unanchored match would also pass on a `continue` moved inside the notice
# branch, which is exactly the regression this pins: every directory that is not
# a chart would then fall through to `helm template`.
# shellcheck disable=SC2016 # the $dir text is matched literally in the YAML
grep -q 'if \[ ! -f "\$dir/Chart.yaml" \]; then' <<<"$BODY" ||
  fail "the loop no longer guards on a missing local Chart.yaml"

grep -q '^                continue$' <<<"$BODY" ||
  fail "no 'continue' at the guard's indentation; a directory without a local Chart.yaml would fall through to helm template"

echo "PASS: ci-gitops.yml announces skipped remote-chart bundles"

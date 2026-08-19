#!/usr/bin/env bash
# The fleet validation warns when a fleet.yaml carries a `helm:` block with a
# `chart:` but no `repo:` — unless the chart comes from an OCI registry. That
# OCI exception used to test for the literal string `"  chart: oci://"`: exactly
# two leading spaces, exactly one space after the colon, no quotes. Renovate and
# most YAML formatters write `chart: "oci://…"`, which is the same document to a
# YAML parser and matched none of it, so a correctly configured OCI bundle got
# `WARNING: <file> has helm chart but missing repo field`. False warnings in an
# otherwise quiet job teach people to ignore it, which is what actually costs
# here.
#
# The sibling `chart:` / `version:` / `repo:` tests were unanchored substring
# matches on `"  <key>:"`. Those happened to survive deeper indentation, since
# any indentation of four or more spaces contains the two-space prefix — but
# they matched just as happily inside a comment or a value, and they carried no
# statement about where the key sits. They are pinned here as anchored patterns
# so the block gate stays keyed to a real indented key and cannot drift back to
# a shape whose correctness was accidental.
#
# Unlike the render-loop test next door, these assertions run the logic rather
# than grep its spelling: the checks are plain `grep` against a file, with no
# runner context, so the real behaviour is reachable from a fixture. Pinning the
# pattern text would pass on any rewrite that keeps the regex and breaks the
# semantics.
#
# Run: scripts/tests/test-ci-gitops-fleet-key-matching.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORKFLOW="$REPO/.github/workflows/ci-gitops.yml"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -f "$WORKFLOW" ] || fail "ci-gitops.yml not found at $WORKFLOW"

# --- extract the four key patterns from the step body ------------------------

# Anchored on the step name, then on its `run: |`, so the `env:` block between
# them cannot satisfy an assertion meant for the shell body — same anchoring as
# test-ci-gitops-oci-skip-notice.sh.
STEP_LINE="$(grep -n '^      - name: Validate Fleet Configurations$' "$WORKFLOW" | cut -d: -f1 || true)"
[ -n "$STEP_LINE" ] || fail "no 'Validate Fleet Configurations' step found"
[ "$(grep -c . <<<"$STEP_LINE")" -eq 1 ] || fail "expected exactly one fleet validation step"

RUN_OFFSET="$(sed -n "${STEP_LINE},\$p" "$WORKFLOW" | grep -n '^        run: |$' | head -1 | cut -d: -f1 || true)"
[ -n "$RUN_OFFSET" ] || fail "the fleet validation step has no 'run: |' body"

BODY_START=$((STEP_LINE + RUN_OFFSET))

# The body ends at the next step, with the next job key as the fallback for the
# case where this is the last step in its job. Bounding on the job alone would
# let later steps fall inside the range and satisfy an assertion meant for this
# one.
END_OFFSET="$(sed -n "$((BODY_START + 1)),\$p" "$WORKFLOW" | grep -n '^      - name: \|^  [a-z]' | head -1 | cut -d: -f1 || true)"
[ -n "$END_OFFSET" ] || fail "could not find the end of the fleet validation step's body"

BODY="$(sed -n "${BODY_START},$((BODY_START + END_OFFSET - 1))p" "$WORKFLOW")"

# Pull each `grep -Eq "<pattern>" "$file"` out of the body and run it against
# the fixtures below. Taking the pattern from the workflow rather than restating
# it is the point: a copy here would keep passing after the workflow regressed.
#
# The pattern is delimited by the literal `" "$file"` that follows it, not by
# the next double quote — the OCI pattern contains an escaped `\"` of its own,
# so a non-greedy match on `"` would truncate it mid-bracket.
extract_pattern() {
  local line="$1"
  line="${line#*grep -Eq \"}"
  line="${line%%\" \"\$file\"*}"
  # In the workflow the pattern sits in a double-quoted shell word, so bash
  # quote-removes `\"` to `"` before grep ever sees it. Extracting the raw YAML
  # text skips that step, so undo it here — otherwise the bracket expression
  # would carry a stray backslash the job's grep never gets.
  printf '%s' "${line//\\\"/\"}"
}

pattern_for() {
  local key="$1" line
  line="$(grep -F "grep -Eq \"^[[:space:]]+${key}" <<<"$BODY" | head -1 || true)"
  [ -n "$line" ] || fail "no anchored 'grep -Eq' test for the ${key} key remains in the fleet validation step"
  extract_pattern "$line"
}

# `chart:` appears twice — the block gate and the OCI exception. The gate is the
# one that does not mention oci://.
CHART_PATTERN="$(extract_pattern "$(grep -F 'grep -Eq "^[[:space:]]+chart:' <<<"$BODY" | grep -Fv 'oci://' | head -1 || true)")"
[ -n "$CHART_PATTERN" ] || fail "no anchored 'grep -Eq' test for the chart: block gate remains in the fleet validation step"
VERSION_PATTERN="$(pattern_for 'version:')"
REPO_PATTERN="$(pattern_for 'repo:')"

OCI_LINE="$(grep -F 'grep -Eq "' <<<"$BODY" | grep -F 'oci://' | head -1 || true)"
[ -n "$OCI_LINE" ] || fail "the OCI exception is gone; every OCI bundle without a repo field would be warned about"
OCI_PATTERN="$(extract_pattern "$OCI_LINE")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# assert_match <pattern> <should-match: yes|no> <label> <yaml…>
assert_match() {
  local pattern="$1" expect="$2" label="$3"
  shift 3
  local file="$WORK/fleet.yaml"
  printf '%s\n' "$@" >"$file"
  if grep -Eq "$pattern" "$file"; then
    [ "$expect" = yes ] || fail "$label: pattern matched but must not"
  else
    [ "$expect" = no ] || fail "$label: pattern did not match but must"
  fi
}

# --- 1. the OCI exception tolerates every valid spelling ----------------------

# These four are the same document to a YAML parser. The unquoted two-space form
# is the only one the old literal matched; the quoted ones are what Renovate and
# YAML formatters produce, and they are the regression this test exists for.
assert_match "$OCI_PATTERN" yes "unquoted OCI chart" \
  'helm:' '  chart: oci://ghcr.io/example/chart' '  version: 1.0.0'
assert_match "$OCI_PATTERN" yes "double-quoted OCI chart" \
  'helm:' '  chart: "oci://ghcr.io/example/chart"' '  version: 1.0.0'
assert_match "$OCI_PATTERN" yes "single-quoted OCI chart" \
  'helm:' "  chart: 'oci://ghcr.io/example/chart'" '  version: 1.0.0'
assert_match "$OCI_PATTERN" yes "extra whitespace after the key" \
  'helm:' '  chart:   oci://ghcr.io/example/chart' '  version: 1.0.0'
assert_match "$OCI_PATTERN" yes "deeper indentation" \
  'helm:' '    chart: oci://ghcr.io/example/chart' '    version: 1.0.0'

# The exception must stay an exception: an HTTP chart still needs its `repo:`,
# so widening the pattern until it matches any chart would silence the warning
# this step exists to emit.
assert_match "$OCI_PATTERN" no "HTTP chart is not an OCI chart" \
  'helm:' '  chart: nginx' '  repo: https://charts.example.com' '  version: 1.0.0'

# A chart named after the registry scheme is not a registry reference. Anchoring
# on the key is what separates them; a bare `oci://` search would not.
assert_match "$OCI_PATTERN" no "oci:// in a value of another key" \
  'helm:' '  chart: nginx' '  repo: https://charts.example.com' '  version: 1.0.0' \
  '  values:' '    note: oci://not-a-chart-reference'

# --- 2. the sibling keys match the same spellings -----------------------------

# `chart:` gates the entire block: when it does not match, the missing-version
# ERROR below it never runs, so a broken bundle passes the job silently. That is
# the more expensive half of the same bug.
assert_match "$CHART_PATTERN" yes "quoted chart value" \
  'helm:' '  chart: "oci://ghcr.io/example/chart"'
assert_match "$CHART_PATTERN" yes "four-space chart key" \
  'helm:' '    chart: nginx'
assert_match "$VERSION_PATTERN" yes "quoted version value" \
  'helm:' '  chart: nginx' '  version: "1.0.0"'
assert_match "$VERSION_PATTERN" yes "four-space version key" \
  'helm:' '  chart: nginx' '    version: 1.0.0'
assert_match "$REPO_PATTERN" yes "quoted repo value" \
  'helm:' '  chart: nginx' '  repo: "https://charts.example.com"'
assert_match "$REPO_PATTERN" yes "four-space repo key" \
  'helm:' '  chart: nginx' '    repo: https://charts.example.com'

# All three keys stay indented: a top-level `chart:` is not inside the `helm:`
# block, and matching it would take the block's checks off an unrelated key.
assert_match "$CHART_PATTERN" no "top-level chart key" 'chart: nginx'
assert_match "$VERSION_PATTERN" no "top-level version key" 'version: 1.0.0'
assert_match "$REPO_PATTERN" no "top-level repo key" 'repo: https://charts.example.com'

# The keys are anchored to the start of the line, so a mention inside a comment
# is not a key. The previous unanchored `grep -q "  chart:"` matched this file
# and pulled a bundle with no chart at all into the version/repo checks.
assert_match "$CHART_PATTERN" no "chart mentioned in a comment" \
  'helm:' '  releaseName: app' '  # no  chart: here, just a note'

# --- 3. the warning itself is still reachable ---------------------------------

# The fix must not remove the check it makes accurate. Without this, a rewrite
# that deletes the warning outright would pass every assertion above. Anchored
# on the `echo` rather than the bare phrase: the step comment above the greps
# quotes the warning text, so a phrase-only match would pass on the comment.
# shellcheck disable=SC2016 # the $file text is matched literally in the YAML
grep -qF 'echo "WARNING: $file has helm chart but missing repo field' <<<"$BODY" ||
  fail "the missing-repo warning is gone from the fleet validation step"
# shellcheck disable=SC2016 # the $file text is matched literally in the YAML
grep -qF 'echo "ERROR: $file has helm chart but missing version field' <<<"$BODY" ||
  fail "the missing-version error is gone from the fleet validation step"

echo "PASS: ci-gitops.yml matches fleet.yaml helm keys regardless of quoting and indentation"

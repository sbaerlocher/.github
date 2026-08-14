#!/usr/bin/env bash
# The govulncheck gate in ci-go.yml reports its findings twice: as log
# annotations and as a job-summary block. The summary is the copy that survives
# log retention and an inaccessible log API, so it is the one a red gate is
# diagnosed from — and it is only worth anything if it is written on the failing
# path. A summary block placed after the `exit 1` would leave every green run
# annotated and every red run blind, which is the exact state this guard was
# added to end.
#
# Checked here: the summary write sits above the gating `exit 1`, both live in
# the same step (each `run:` is its own shell, so an earlier step would not see
# the values), and the block covers both finding classes. The rendering itself
# is read out of ci-go.yml and executed against real values, so the behaviour
# under test is the shipped one — same arrangement as
# test-ci-go-postgres-env-guard.sh for the $GITHUB_ENV guards in this file.
#
# Run: scripts/tests/test-ci-go-govulncheck-summary.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORKFLOW="$REPO/.github/workflows/ci-go.yml"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# --- placement -------------------------------------------------------------

# `|| true` on the greps: under `set -euo pipefail` a non-matching grep would
# abort at the assignment, turning the drift this file exists to catch into a
# bare non-zero exit instead of the diagnostic below.
# shellcheck disable=SC2016 # the $GITHUB_STEP_SUMMARY text is matched literally in the YAML
SUMMARY_LINE="$(grep -n '>> "\$GITHUB_STEP_SUMMARY"' "$WORKFLOW" | cut -d: -f1 || true)"
[ -n "$SUMMARY_LINE" ] || fail "no \$GITHUB_STEP_SUMMARY write found in ci-go.yml"
[ "$(grep -c . <<<"$SUMMARY_LINE")" -eq 1 ] ||
  fail "expected exactly one \$GITHUB_STEP_SUMMARY write in ci-go.yml"

GATE_LINE="$(grep -n '::warning::Reachable vulnerabilities detected' "$WORKFLOW" | cut -d: -f1 || true)"
[ -n "$GATE_LINE" ] || fail "no reachable-findings gate found in ci-go.yml"

[ "$SUMMARY_LINE" -lt "$GATE_LINE" ] ||
  fail "summary write is at line $SUMMARY_LINE, below the gate at $GATE_LINE"

# Above the gate is not enough — a summary moved into an earlier step would
# still be "above" it while running in a different shell, where neither
# $reachable nor $imported exists.
STEP_START="$(grep -n '^ *- name: Run govulncheck$' "$WORKFLOW" | cut -d: -f1 || true)"
[ -n "$STEP_START" ] || fail "no 'Run govulncheck' step found in ci-go.yml"
if sed -n "${SUMMARY_LINE},${GATE_LINE}p" "$WORKFLOW" | grep -q '^ *- name:'; then
  fail "summary write and the gate are in different steps"
fi
[ "$STEP_START" -lt "$SUMMARY_LINE" ] ||
  fail "summary write at line $SUMMARY_LINE is not inside the 'Run govulncheck' step"

# The gate must still fail the job. Making the findings visible must not turn
# the gate into a report — every other assertion here would stay green if the
# `exit 1` disappeared.
sed -n "${GATE_LINE},\$p" "$WORKFLOW" | sed -n '1,5p' | grep -q '^ *exit 1$' ||
  fail "reachable findings no longer exit non-zero"

# --- artifact upload -------------------------------------------------------

# The raw report is the second half of the diagnosis: `if: always()` because the
# fail case is the one that needs it, and matrix-scoped because the other two
# matrix legs never produce the file.
UPLOAD_LINE="$(grep -n '^ *- name: Upload govulncheck report$' "$WORKFLOW" | cut -d: -f1 || true)"
[ -n "$UPLOAD_LINE" ] || fail "no govulncheck artifact upload step found in ci-go.yml"
UPLOAD_BLOCK="$(sed -n "${UPLOAD_LINE},$((UPLOAD_LINE + 10))p" "$WORKFLOW")"
grep -q "if: always() && matrix.scanner == 'govulncheck'" <<<"$UPLOAD_BLOCK" ||
  fail "govulncheck upload is not 'if: always()' and scoped to the govulncheck matrix leg"
grep -q 'path: govulncheck.json' <<<"$UPLOAD_BLOCK" ||
  fail "govulncheck upload does not carry govulncheck.json"
grep -q 'uses: actions/upload-artifact@[0-9a-f]\{40\} # v' <<<"$UPLOAD_BLOCK" ||
  fail "govulncheck upload does not pin upload-artifact to a SHA with a version comment"

# --- rendering -------------------------------------------------------------

# The summary block is read out of the workflow and run against real values, so
# a changed heading or a dropped finding class surfaces here. The extracted text
# is the `{ ... } >> "$GITHUB_STEP_SUMMARY"` group, de-indented; `eval` runs a
# block from a tracked file in this repo, not from input.
BLOCK_START="$(sed -n "${STEP_START},${SUMMARY_LINE}p" "$WORKFLOW" |
  grep -n '^ *{$' | tail -1 | cut -d: -f1 || true)"
[ -n "$BLOCK_START" ] || fail "no '{' opening the summary block found in ci-go.yml"
BLOCK_START=$((STEP_START + BLOCK_START - 1))
SUMMARY_BODY="$(sed -n "$((BLOCK_START + 1)),$((SUMMARY_LINE - 1))p" "$WORKFLOW" |
  sed 's/^          //')"
[ -n "$SUMMARY_BODY" ] || fail "summary block in ci-go.yml is empty"

render() {
  # shellcheck disable=SC2034 # both are read by the summary block inside the eval below
  local reachable="$1" imported="$2"
  eval "$SUMMARY_BODY"
}

OUT="$(render "GO-2026-1234" "GO-2026-9999")"
grep -q 'GO-2026-1234' <<<"$OUT" || fail "summary omits a reachable finding"
grep -q 'GO-2026-9999' <<<"$OUT" || fail "summary omits an import-only finding"
grep -q 'Reachable' <<<"$OUT" || fail "summary does not label the gating class"
grep -q 'Import-only' <<<"$OUT" || fail "summary does not label the non-gating class"

# Multiple IDs arrive as a newline-separated list from `sort -u`; they must all
# survive, not just the first line.
OUT="$(render "$(printf 'GO-2026-1111\nGO-2026-2222')" "")"
grep -q 'GO-2026-1111' <<<"$OUT" || fail "summary drops the first of several reachable findings"
grep -q 'GO-2026-2222' <<<"$OUT" || fail "summary drops the second of several reachable findings"

# The clean run must say so rather than render an empty section — an empty
# summary is indistinguishable from a summary that was never written.
OUT="$(render "" "")"
grep -q 'No reachable vulnerabilities' <<<"$OUT" ||
  fail "summary does not report a clean run"
grep -q 'Import-only' <<<"$OUT" &&
  fail "summary renders the import-only section when there are no such findings"

# Import-only findings alone: the run stays green, and the notices are still the
# only record of what govulncheck saw.
OUT="$(render "" "GO-2026-7777")"
grep -q 'GO-2026-7777' <<<"$OUT" || fail "summary omits import-only findings on a green run"
grep -q 'No reachable vulnerabilities' <<<"$OUT" ||
  fail "summary does not report the green gate alongside import-only findings"

echo "PASS: ci-go.yml govulncheck summary and report artifact"

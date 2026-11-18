#!/usr/bin/env bash
# Drift check: the workflow counts stated in README.md must match
# what is actually in .github/workflows/.
#
# Three places used to carry a count and no two agreed (24 / "24 + 1 self-test"
# / 27 in the repo description) — a hand-maintained number drifts on every
# workflow added. README.md is now the only place that states one; AGENTS.md
# carries none, so it cannot seed a wrong count.
#
# Counts are derived, never hardcoded here: reusable is the number declaring a
# `workflow_call` trigger, internal is the remainder; total only feeds the PASS
# line. Internal workflows are not checked by name: no doc lists them any more,
# so a rename that keeps the counts passes by design.
#
# Run: scripts/tests/test-workflow-counts.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORKFLOWS="$REPO/.github/workflows"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# Classification is shared with scripts/tests/test-workflow-input-injection.sh,
# which derives the set it scans for injection sinks from the same `workflow_call`
# trigger. Two copies could drift apart while both tests stayed green, and then
# the guard's coverage line would stop meaning what the counts below assert.
CLASSIFIED="$("$HERE/../list-reusable-workflows.sh" "$WORKFLOWS")" ||
  fail "could not classify the workflow files"

[ -n "$CLASSIFIED" ] || fail "no workflow files found in $WORKFLOWS"

TOTAL="$(wc -l <<<"$CLASSIFIED" | tr -d ' ')"
REUSABLE="$(grep -c '^reusable' <<<"$CLASSIFIED" || true)"
INTERNAL="$(grep -c '^internal' <<<"$CLASSIFIED" || true)"
README="$REPO/README.md"

# README states the reusable count and the internal count.
grep -qF "**Reusable workflows:** $REUSABLE (plus $INTERNAL internal to this repo)" "$README" ||
  fail "README.md: must state '**Reusable workflows:** $REUSABLE (plus $INTERNAL internal to this repo)'"

echo "PASS: workflow counts ($TOTAL files = $REUSABLE reusable + $INTERNAL internal) match README.md"

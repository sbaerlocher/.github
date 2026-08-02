#!/usr/bin/env bash
# Drift check: the workflow counts stated in AGENTS.md and README.md must match
# what is actually in .github/workflows/.
#
# Three places used to carry a count and no two agreed (24 / "24 + 1 self-test"
# / 27 in the repo description) — a hand-maintained number drifts on every
# workflow added. AGENTS.md is the first file an agent reads, so a wrong count
# there seeds wrong assumptions about the repo for a whole session.
#
# Counts are derived, never hardcoded here: total is the file count, reusable is
# the number carrying a `workflow_call` trigger, internal is the remainder. The
# docs are then grepped for those derived values.
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

shopt -s nullglob
FILES=("$WORKFLOWS"/*.yml)
shopt -u nullglob

TOTAL=${#FILES[@]}
[ "$TOTAL" -gt 0 ] || fail "no workflow files found in $WORKFLOWS"

REUSABLE=0
INTERNAL_FILES=()
for f in "${FILES[@]}"; do
  # `workflow_call:` under `on:` is what makes a workflow consumable by another
  # repo. Matching the bare token is enough — no other construct uses it.
  if grep -q 'workflow_call' "$f"; then
    REUSABLE=$((REUSABLE + 1))
  else
    INTERNAL_FILES+=("$(basename "$f")")
  fi
done
INTERNAL=$((TOTAL - REUSABLE))

AGENTS="$REPO/AGENTS.md"
README="$REPO/README.md"

# 1 — AGENTS.md "Current Statistics" states total, reusable and internal.
STATS_LINE="$(grep -n '\*\*Total Workflows\*\*' "$AGENTS" || true)"
[ -n "$STATS_LINE" ] || fail "AGENTS.md: '**Total Workflows**' line not found"

# The statement wraps over several lines; read the whole bullet.
STATS_START="${STATS_LINE%%:*}"
STATS_BLOCK="$(sed -n "${STATS_START},$((STATS_START + 3))p" "$AGENTS")"

grep -q "$TOTAL files" <<<"$STATS_BLOCK" ||
  fail "AGENTS.md: statistics must state '$TOTAL files' (found $TOTAL workflow files)"
grep -q "$REUSABLE reusable" <<<"$STATS_BLOCK" ||
  fail "AGENTS.md: statistics must state '$REUSABLE reusable' (found $REUSABLE with workflow_call)"
grep -q "$INTERNAL internal" <<<"$STATS_BLOCK" ||
  fail "AGENTS.md: statistics must state '$INTERNAL internal' (found $INTERNAL without workflow_call)"

# Every internal workflow is named there — that list is the actually useful bit.
for name in "${INTERNAL_FILES[@]}"; do
  grep -q "$name" <<<"$STATS_BLOCK" ||
    fail "AGENTS.md: statistics must name the internal workflow '$name'"
done

# 2 — the repository-structure tree repeats the same numbers.
grep -q "# $TOTAL files: $REUSABLE reusable + $INTERNAL internal" "$AGENTS" ||
  fail "AGENTS.md: workflows/ tree comment must read '# $TOTAL files: $REUSABLE reusable + $INTERNAL internal'"

# 3 — the "Internal Workflows (N)" section heading and one row per workflow.
grep -q "^### Internal Workflows ($INTERNAL)$" "$AGENTS" ||
  fail "AGENTS.md: heading must read '### Internal Workflows ($INTERNAL)'"

for name in "${INTERNAL_FILES[@]}"; do
  grep -q "\`$name\`" "$AGENTS" ||
    fail "AGENTS.md: Internal Workflows table must have a row for '$name'"
done

# 4 — README states the reusable count and the internal count.
grep -q "\*\*Reusable workflows:\*\* $REUSABLE (plus $INTERNAL internal to this repo)" "$README" ||
  fail "README.md: must state '**Reusable workflows:** $REUSABLE (plus $INTERNAL internal to this repo)'"

echo "PASS: workflow counts ($TOTAL files = $REUSABLE reusable + $INTERNAL internal) match AGENTS.md and README.md"

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
# the number declaring a `workflow_call` trigger, internal is the remainder. The
# docs are then checked against those derived values.
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

command -v python3 >/dev/null 2>&1 || fail "python3 required to parse the workflow YAML"

# Classification is done on the parsed `on:` mapping, not by grepping for the
# bare token: `workflow_call` also appears in prose comments (e.g.
# ai-claude-review.yml, ops-drift-issue.yml), which would misclassify an
# internal workflow as reusable. Both .yml and .yaml are collected — GitHub
# loads either, and a workflow added with the other extension would otherwise
# be invisible to every count while the check still passed.
CLASSIFIED="$(
  python3 - "$WORKFLOWS" <<'PY'
import os, sys, glob, yaml

workflows = sys.argv[1]
paths = sorted(glob.glob(os.path.join(workflows, "*.yml")) +
               glob.glob(os.path.join(workflows, "*.yaml")))

for path in paths:
    with open(path) as fh:
        doc = yaml.safe_load(fh) or {}
    # YAML 1.1 resolves an unquoted `on:` key to the boolean True.
    triggers = doc.get("on", doc.get(True))
    # All three trigger spellings count: the block mapping (`on:\n  workflow_call:`),
    # the flow sequence (`on: [workflow_call]`) and the bare scalar
    # (`on: workflow_call`). Accepting only the mapping would undercount.
    if isinstance(triggers, dict):
        reusable = "workflow_call" in triggers
    elif isinstance(triggers, list):
        reusable = "workflow_call" in triggers
    else:
        reusable = triggers == "workflow_call"
    print(f"{'reusable' if reusable else 'internal'}\t{os.path.basename(path)}")
PY
)" || fail "could not parse the workflow files"

[ -n "$CLASSIFIED" ] || fail "no workflow files found in $WORKFLOWS"

TOTAL="$(wc -l <<<"$CLASSIFIED" | tr -d ' ')"
REUSABLE="$(grep -c '^reusable' <<<"$CLASSIFIED" || true)"
INTERNAL="$(grep -c '^internal' <<<"$CLASSIFIED" || true)"
# Plain read loop rather than `mapfile`: that is a bash 4 builtin and this repo
# still targets the bash 3.2 that macOS ships.
INTERNAL_FILES=()
while IFS= read -r name; do
  [ -n "$name" ] && INTERNAL_FILES+=("$name")
done < <(awk -F'\t' '$1 == "internal" { print $2 }' <<<"$CLASSIFIED")

AGENTS="$REPO/AGENTS.md"
README="$REPO/README.md"

# Counts are matched with a leading boundary so a longer number cannot satisfy a
# shorter assertion (`24 internal` must not pass for INTERNAL=4, `128 files` must
# not pass for TOTAL=28).
has_count() { # has_count <file-or-text> <number> <unit>
  grep -qE "(^|[^0-9])$2 $3" <<<"$1"
}

# 1 — AGENTS.md "Current Statistics" states total, reusable and internal.
STATS_START="$(awk '/\*\*Total Workflows\*\*/ { print NR; exit }' "$AGENTS")"
[ -n "$STATS_START" ] || fail "AGENTS.md: '**Total Workflows**' line not found"

# The bullet wraps over several lines; take it up to (not including) the next
# list item, so the window follows the prose instead of a hardcoded length.
# awk reads the file itself and stops printing at the next list item; piping
# `tail` into an early-exiting awk would raise SIGPIPE under `pipefail`.
STATS_BLOCK="$(
  awk -v start="$STATS_START" '
    NR < start { next }
    NR > start && /^- / { done = 1 }
    !done { print }
  ' "$AGENTS"
)"

has_count "$STATS_BLOCK" "$TOTAL" "files" ||
  fail "AGENTS.md: statistics must state '$TOTAL files' (found $TOTAL workflow files)"
has_count "$STATS_BLOCK" "$REUSABLE" "reusable" ||
  fail "AGENTS.md: statistics must state '$REUSABLE reusable' (found $REUSABLE with workflow_call)"
has_count "$STATS_BLOCK" "$INTERNAL" "internal" ||
  fail "AGENTS.md: statistics must state '$INTERNAL internal' (found $INTERNAL without workflow_call)"

# Every internal workflow is named there — that list is the actually useful bit.
for name in "${INTERNAL_FILES[@]}"; do
  grep -qF "$name" <<<"$STATS_BLOCK" ||
    fail "AGENTS.md: statistics must name the internal workflow '$name'"
done

# 2 — the repository-structure tree repeats the same numbers.
grep -qF "# $TOTAL files: $REUSABLE reusable + $INTERNAL internal" "$AGENTS" ||
  fail "AGENTS.md: workflows/ tree comment must read '# $TOTAL files: $REUSABLE reusable + $INTERNAL internal'"

# 3 — the "Internal Workflows (N)" section heading, plus one table row per
# internal workflow. Scoped to the section so it cannot be satisfied by the
# mention in the statistics bullet above.
grep -qE "^### Internal Workflows \($INTERNAL\)$" "$AGENTS" ||
  fail "AGENTS.md: heading must read '### Internal Workflows ($INTERNAL)'"

# Stop at the next heading of any level, not just `### ` — the Composite
# Actions section that follows starts with `## ` and carries its own table.
SECTION="$(
  awk '/^### Internal Workflows \(/ { inside = 1; next }
       inside && /^#{1,6} / { exit }
       inside && /^\| / { print }' "$AGENTS"
)"
[ -n "$SECTION" ] || fail "AGENTS.md: Internal Workflows section has no table rows"

for name in "${INTERNAL_FILES[@]}"; do
  grep -qF "\`$name\`" <<<"$SECTION" ||
    fail "AGENTS.md: Internal Workflows table must have a row for '$name'"
done

# 4 — README states the reusable count and the internal count.
grep -qF "**Reusable workflows:** $REUSABLE (plus $INTERNAL internal to this repo)" "$README" ||
  fail "README.md: must state '**Reusable workflows:** $REUSABLE (plus $INTERNAL internal to this repo)'"

echo "PASS: workflow counts ($TOTAL files = $REUSABLE reusable + $INTERNAL internal) match AGENTS.md and README.md"

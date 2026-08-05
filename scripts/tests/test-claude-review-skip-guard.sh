#!/usr/bin/env bash
# Self-check for the workflow-validation skip branch in ai-claude-review.yml.
#
# The action refuses to run when the PR changes a workflow file that differs
# from the default branch, and reports that as a *skip*: it sets the step
# output `skipped_due_to_workflow_validation_mismatch` and returns without
# failing. The assertion step reads that output to report a skip instead of a
# missing review. The wiring is a plain string reference through
# `steps.<id>.outputs.<name>` — GitHub Actions resolves an unknown `steps.*`
# expression to the empty string rather than erroring, so every way of breaking
# it is silent at runtime and only visible here.
#
# Everything is derived from the file, nothing is hardcoded: the step id is read
# out of the workflow and then required in the guard, so renaming the id in one
# place and not the other fails.
#
# Run: scripts/tests/test-claude-review-skip-guard.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORKFLOW="${1:-$REPO/.github/workflows/ai-claude-review.yml}"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -f "$WORKFLOW" ] || fail "workflow not found: $WORKFLOW"

SKIP_OUTPUT='skipped_due_to_workflow_validation_mismatch'

# 1 — the action step carries an `id`.
#
# The candidate is reset at every step boundary (`      - `). Without that reset
# a step with no `id` of its own would inherit the previous step's id from the
# scan and the assertion would pass against a file where the wiring is in fact
# broken.
# `id:` is matched both as the first key of a step (`      - id: x`) and as a
# later key (`        id: x`), because YAML allows either and the workflow uses
# the former.
STEP_ID="$(
  awk '
    /^      - / { id = "" }
    /^ *-? *id: / { id = $NF }
    /uses: anthropics\/claude-code-action@/ { print id; exit }
  ' "$WORKFLOW"
)"

[ -n "$STEP_ID" ] || fail "the anthropics/claude-code-action step needs an \`id:\` — without it its outputs cannot be addressed and the skip branch can never fire"

# The guard body: from the assertion step to the end of the file.
GUARD="$(
  awk '/^      - name: Assert a review was posted$/ { inside = 1 }
       inside { print }' "$WORKFLOW"
)"
[ -n "$GUARD" ] || fail "step 'Assert a review was posted' not found"

# 2 — the guard reads the skip output under exactly that id.
grep -qF "steps.$STEP_ID.outputs.$SKIP_OUTPUT" <<<"$GUARD" ||
  fail "the guard must read \`steps.$STEP_ID.outputs.$SKIP_OUTPUT\` — an unknown \`steps.*\` reference resolves to the empty string, so a renamed id disables the skip branch silently"

# 3 — the skip branch ends in `exit 0`.
#
# Scoped to the branch, not the file: the guard already has an `exit 0` on the
# "review found" path, so a bare `grep -q 'exit 0'` would have passed before
# this change existed.
SKIP_BRANCH="$(
  awk '/if \[ "\$\{SKIPPED:-\}" = "true" \]; then/ { inside = 1 }
       inside { print }
       inside && /^          fi$/ { exit }' <<<"$GUARD"
)"
[ -n "$SKIP_BRANCH" ] || fail "no \`if [ \"\${SKIPPED:-}\" = \"true\" ]\` branch in the guard"
grep -qE '^ *exit 0$' <<<"$SKIP_BRANCH" ||
  fail "the skip branch must end in \`exit 0\` — otherwise it falls through into the missing-review path and the check goes red on exactly the runs it is meant to explain"

# 4 — the regular path still fails.
grep -qE '^ *exit 1$' <<<"$GUARD" ||
  fail "the guard must still \`exit 1\` when no review was posted"

# 5 — the two markers exist, appear once each, and differ. A shared marker would
# make the upsert check see the other state's comment and suppress this one.
MISSING_MARKER='<!-- claude-review-missing -->'
SKIPPED_MARKER='<!-- claude-review-skipped -->'

[ "$MISSING_MARKER" != "$SKIPPED_MARKER" ] || fail "the two comment markers must differ"

for marker in "$MISSING_MARKER" "$SKIPPED_MARKER"; do
  COUNT="$(grep -cF "$marker" "$WORKFLOW" || true)"
  [ "$COUNT" -eq 1 ] ||
    fail "marker '$marker' must be defined exactly once in the workflow (found $COUNT) — the branches reference it through their env var, not by repeating the literal"
done

echo "PASS: claude review skip guard wired through id '$STEP_ID'"

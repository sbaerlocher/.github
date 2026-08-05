#!/usr/bin/env bash
# The claude-code-action skips itself when the triggering workflow file differs
# from the one on the default branch: it warns and returns without failing, so
# the step ends green in seconds with no review posted. The assertion step in
# ai-claude-review.yml tells that skip apart from a genuinely missing review by
# reading the action's `github_token` output, which arrives empty on a skip.
#
# That channel is an undocumented implementation detail of the action, and its
# failure direction is green: an unknown `steps.*` resolves to the empty string,
# and empty means "skipped" here. A rename on this side would therefore make the
# skip branch fire on *every* run and take the check green on unreviewed diffs,
# silently. This file pins the wiring so that edit fails loudly instead.
#
# Everything is derived from the workflow rather than hard-coded, so the file
# under test is the shipped one: the id is read out of the action step and the
# guard's reference is then checked against whatever was read, which catches a
# one-sided rename while leaving a consistent one free.
#
# Run: scripts/tests/test-claude-review-skip-guard.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORKFLOW="$REPO/.github/workflows/ai-claude-review.yml"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -f "$WORKFLOW" ] || fail "ai-claude-review.yml not found at $WORKFLOW"

# --- 1. the action step carries an id ----------------------------------------

# The candidate is reset at every `      - ` step boundary. Without that reset a
# step with no id of its own would inherit the previous step's (`mode`), and the
# assertion would pass on a file where the id had been dropped — the exact
# regression this check exists for.
#
# Both key orderings are accepted. YAML mapping keys are unordered, so `uses:`
# first and `id:` first are the same step; matching only the latter would report
# "the step has no id" on a file that has one, which is a loud failure with a
# misleading cause. The `uses:` line therefore only records that the step is the
# one under test, and the id is printed at the following step boundary or at EOF.
# `done` rather than a bare `exit`: awk still runs the END block after `exit`,
# so without it the id is printed twice and every pattern built from it below
# carries an embedded newline and matches nothing — a green run on any file.
ACTION_ID="$(awk '
  /^      - / { if (found) { print id; done = 1; exit } id = "" }
  /^ *(- )?id: / { id = $NF }
  /^ *(- )?uses: anthropics\/claude-code-action@/ { found = 1 }
  END { if (found && !done) print id }
' "$WORKFLOW")"

# The id must be a single token: an extraction that returned two lines would
# make every pattern built from it match nothing, which fails green.
[ "$(grep -c . <<<"$ACTION_ID")" -eq 1 ] ||
  fail "the id extraction returned more than one line: [$ACTION_ID]"

[ -n "$ACTION_ID" ] ||
  fail "the anthropics/claude-code-action step has no id; its outputs are not addressable"

# --- 2. the guard reads github_token under exactly that id -------------------

# Anchored to the env entry, not matched anywhere in the file: the workflow's
# own comments name this expression in prose, so an unanchored grep stays green
# after the `SKIPPED:` entry is deleted — it would be matching the comment that
# explains the wiring rather than the wiring.
SKIPPED_EXPR="$(sed -n '/^ *SKIPPED: /,/^ *[A-Za-z_-]*:/p' "$WORKFLOW")"
[ -n "$SKIPPED_EXPR" ] || fail "no SKIPPED env entry found in the assertion step"

grep -q "steps\.$ACTION_ID\.outputs\.github_token" <<<"$SKIPPED_EXPR" ||
  fail "the SKIPPED env entry does not read steps.$ACTION_ID.outputs.github_token; a stale id resolves to empty, which means 'skip' and takes the check green on unreviewed diffs"

# The outcome test is what keeps the branch to the state it describes: an empty
# token also describes a step that failed before its token exchange, and the
# assertion step runs under `!cancelled()`, so those runs reach it too.
grep -q "steps\.$ACTION_ID\.outcome == 'success'" <<<"$SKIPPED_EXPR" ||
  fail "the SKIPPED env entry does not require steps.$ACTION_ID.outcome == 'success'; a failed action step would be reported as a validation skip"

# --- locate the guard branches ------------------------------------------------

# Each branch is located by its own condition rather than by a line offset, so
# reordering the guard body cannot silently move an assertion onto the wrong
# block.
# The skip branch is the one that acts on the channel *and* exits; the review
# branch tests the same variable to warn, so the grep is anchored on the `if`
# that opens a block rather than on any mention of the name.
# shellcheck disable=SC2016 # the $SKIPPED text is matched literally in the YAML
SKIP_LINE="$(grep -n '^          if \[ "\$SKIPPED" = "true" \]; then$' "$WORKFLOW" | cut -d: -f1 || true)"
[ -n "$SKIP_LINE" ] || fail "no skip branch guarded by the skip channel found"
[ "$(grep -c . <<<"$SKIP_LINE")" -eq 1 ] || fail "expected exactly one skip branch"

# The red path is anchored on its error line, which only it carries.
RED_LINE="$(grep -n '^ *echo "::error::No review on ' "$WORKFLOW" | cut -d: -f1 || true)"
[ -n "$RED_LINE" ] || fail "no red path found"
[ "$(grep -c . <<<"$RED_LINE")" -eq 1 ] || fail "expected exactly one red path"

[ "$SKIP_LINE" -lt "$RED_LINE" ] ||
  fail "skip branch is at line $SKIP_LINE, below the red path at $RED_LINE — the red path would win"

# The head-SHA review check must come first: it is what bounds the green failure
# direction of the skip channel. Moved below the skip branch, a broken channel
# would swallow real reviews instead of only the doubly-unlucky case.
# shellcheck disable=SC2016 # the $COUNT text is matched literally in the YAML
REVIEW_LINE="$(grep -n '^ *if \[ "\$COUNT" -gt 0 \]; then$' "$WORKFLOW" | cut -d: -f1 || true)"
[ -n "$REVIEW_LINE" ] || fail "no head-SHA review check found"
[ "$REVIEW_LINE" -lt "$SKIP_LINE" ] ||
  fail "review check is at line $REVIEW_LINE, below the skip branch at $SKIP_LINE"

# The review branch carries the runtime detector for a broken channel: a review
# on the head SHA proves the action ran, so a skip reported there can only mean
# the wiring broke. It is the one place that is provable at runtime, which is
# why its loss should not be silent.
sed -n "${REVIEW_LINE},$((SKIP_LINE - 1))p" "$WORKFLOW" | grep -q '::warning::' ||
  fail "the review branch no longer warns when the skip channel reports a skip on a reviewed head SHA"

# --- 3. the skip branch exits green ------------------------------------------

# Scoped to the branch, not the file: an `exit 0` already exists on the
# "review found" path, so a bare `grep -q 'exit 0'` was satisfied before this
# change ever landed and would prove nothing.
sed -n "${SKIP_LINE},$((RED_LINE - 1))p" "$WORKFLOW" | grep -q '^ *exit 0$' ||
  fail "the skip branch does not exit 0"

# --- 4. the regular branch still exits red -----------------------------------

sed -n "${RED_LINE},\$p" "$WORKFLOW" | grep -q '^ *exit 1$' ||
  fail "the red path no longer exits 1"

# --- 5. two distinct markers, one occurrence each -----------------------------

# One shared marker would let the upsert check of one state suppress the other
# state's comment, so the two are asserted to be different as well as present.
MISSING_MARKER="$(sed -n "s/^ *MARKER: '\(.*\)'$/\1/p" "$WORKFLOW")"
SKIP_MARKER="$(sed -n "s/^ *SKIP_MARKER: '\(.*\)'$/\1/p" "$WORKFLOW")"

[ -n "$MISSING_MARKER" ] || fail "no MARKER definition found"
[ -n "$SKIP_MARKER" ] || fail "no SKIP_MARKER definition found"
[ "$(grep -c . <<<"$MISSING_MARKER")" -eq 1 ] || fail "expected exactly one MARKER definition"
[ "$(grep -c . <<<"$SKIP_MARKER")" -eq 1 ] || fail "expected exactly one SKIP_MARKER definition"

[ "$MISSING_MARKER" != "$SKIP_MARKER" ] ||
  fail "both states use the same marker; one upsert check would suppress the other comment"

echo "PASS: ai-claude-review.yml workflow-validation skip guard"

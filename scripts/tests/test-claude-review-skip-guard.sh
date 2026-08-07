#!/usr/bin/env bash
# The claude-code-action skips itself when the triggering workflow file differs
# from the one on the default branch: it warns and returns without failing, so
# the step ends green in seconds with no review posted. The assertion step in
# ai-claude-review.yml has to tell that skip apart from a genuinely missing
# review, or every PR that touches a workflow file gets a permanent red check.
#
# It used to ask the action, by reading its `github_token` output — empty was
# taken to mean "skipped". That channel was an undocumented implementation
# detail whose failure direction was green: an unknown `steps.*` resolves to the
# empty string, and empty meant "skip", so a broken channel took the check green
# on unreviewed diffs. Org-wide it never once fired.
#
# The channel is now established in the assertion step itself: it asks the API
# whether the PR changes a file under `.github/workflows/` that differs from the
# default branch, which is exactly the condition the action refuses to run
# under. Everything runs under `set -euo pipefail`, so a broken channel is red.
#
# This file pins that wiring: the API query, the path filter, the default-branch
# comparison, and the absence of the retired output. It also pins the branch
# order, which is what keeps the review check ahead of the skip branch.
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

# --- 1. the skip channel is established from the PR's changed files ----------

# Scoped to the assertion step's `run:` body rather than the whole file: the
# workflow's own comments name these things in prose, so a file-wide grep would
# stay green on a body that no longer does any of it, matching the comment that
# explains the wiring instead of the wiring.
#
# The body runs from the step's `run: |` to EOF. That is the last step in the
# file, so no end anchor is needed; a step added after it would widen the range,
# which can only add matches, and every assertion below is a positive one whose
# subject is unique to this body.
ASSERT_LINE="$(grep -n '^      - name: Assert a review was posted$' "$WORKFLOW" | cut -d: -f1 || true)"
[ -n "$ASSERT_LINE" ] || fail "no 'Assert a review was posted' step found"
[ "$(grep -c . <<<"$ASSERT_LINE")" -eq 1 ] || fail "expected exactly one assertion step"

BODY="$(sed -n "${ASSERT_LINE},\$p" "$WORKFLOW")"

# The API query is the channel itself: without it the step has no way to know
# whether the PR touches a workflow file.
# shellcheck disable=SC2016 # the $PR text is matched literally in the YAML
grep -q 'pulls/\$PR/files' <<<"$BODY" ||
  fail "the assertion step does not query the PR's changed files; the skip channel has no source"

# The path filter is what makes the answer mean "workflow file", not "any file".
grep -q '\.github/workflows/' <<<"$BODY" ||
  fail "the assertion step does not filter the changed files to .github/workflows/; every PR would be reported as a skip"

# The comparison against the default branch is the other half of the action's
# own condition: a workflow file that matches the default branch does not stop
# the action from running, so changing one is not by itself a skip.
grep -q 'default_branch' <<<"$BODY" ||
  fail "the assertion step does not compare against the default branch; a workflow file identical to the default branch would be reported as a skip"

# The channel has to actually feed the branch below.
grep -q 'SKIPPED=true' <<<"$BODY" ||
  fail "the assertion step never sets SKIPPED=true; the skip branch is unreachable"

# --- 2. the retired action-output channel is gone ----------------------------

# The old channel failed green: an unknown `steps.*` resolves to the empty
# string and empty meant "skipped". Reintroducing it anywhere in this workflow
# brings that failure direction back, so it is asserted absent file-wide rather
# than only in the step body.
# `if grep`, not `grep && fail`: under `set -e` the latter would end the script
# on the no-match case — the passing one — with the exit status of the failed
# grep, reporting the healthy file as a failure with no message.
if grep -q 'outputs\.github_token' "$WORKFLOW"; then
  fail "the workflow still reads outputs.github_token; that channel fails green on unreviewed diffs and was replaced by the changed-files check"
fi

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

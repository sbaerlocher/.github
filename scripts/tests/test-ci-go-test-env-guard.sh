#!/usr/bin/env bash
# $GITHUB_ENV is line-based, so a line break inside a `test-env-vars` value turns
# one entry into several. Setting arbitrary variables is what the input is for, so
# the escalation is not "a caller can set GOFLAGS" — it is the narrower case where
# the keys are the caller's but a value is interpolated from untrusted data (a PR
# title, a branch name): that value then writes entries of its own, for every
# following step of the job.
#
# The runner splits on LF and CRLF only (`ReadLine` in
# `src/Runner.Worker/FileCommandManager.cs` searches for `\n`), so rejecting `\n`
# already covers both terminators; `\r` is rejected as defence in depth, not
# because a lone CR splits a line today.
#
# ci-go.yml rejects such values before writing the file; this checks the
# rejecting jq expression actually does that.
#
# The expression is read out of ci-go.yml rather than repeated here, so the two
# cannot drift: a guard edited in the workflow is the guard under test. The
# workflow has a single `test-and-lint` job, so the guard must appear exactly
# once — a second copy means the job was split again and the two can drift, the
# failure mode this repo already had.
#
# Run: scripts/tests/test-ci-go-test-env-guard.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORKFLOW="$REPO/.github/workflows/ci-go.yml"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq required"

# One line per occurrence, leading whitespace and the trailing redirect stripped.
GUARDS="$(sed -n "s/.*| jq -e '\(.*\)' >\/dev\/null.*/\1/p" "$WORKFLOW")"
[ -n "$GUARDS" ] || fail "no 'jq -e' guard found in ci-go.yml"

COUNT="$(grep -c . <<<"$GUARDS")"
[ "$COUNT" -eq 1 ] ||
  fail "expected exactly one guard in ci-go.yml, found $COUNT occurrence(s)"

GUARD="$(head -n 1 <<<"$GUARDS")"

# accept <label> <json> — value has no line break, the step must proceed.
accept() {
  printf '%s' "$2" | jq -e "$GUARD" >/dev/null ||
    fail "guard rejects a legitimate input: $1"
}

# reject <label> <json> — value carries a line break, the step must stop.
reject() {
  if printf '%s' "$2" | jq -e "$GUARD" >/dev/null 2>&1; then
    fail "guard accepts an injecting input: $1"
  fi
}

accept "single-line entries" '{"API_URL":"http://localhost","MSG":"a b"}'
accept "empty object" '{}'
accept "non-string values" '{"PORT":5432,"DEBUG":true}'
accept "value containing a literal backslash-n" '{"MSG":"a\\nb"}'
accept "value containing a literal backslash-r" '{"MSG":"a\\rb"}'
reject "newline in a value" '{"MSG":"harmless\nPATH=/tmp/evil"}'
reject "newline in the second of two values" '{"API":"a b","MSG":"x\nGOFLAGS=-tags=evil"}'
reject "trailing newline in a value" '{"MSG":"value\n"}'

# A key carries the same injection: `{"A\nPATH=/tmp/evil":"x"}` renders as two
# lines, the second of which is a complete assignment.
reject "newline in a key" '{"MSG\nPATH=/tmp/evil":"x"}'
reject "newline in the second of two keys" '{"API":"a b","MSG\nLD_PRELOAD=/tmp/evil.so":"x"}'

# A lone CR is not a terminator for today's runner, so these two are defence in
# depth rather than a closed hole: the guard stops depending on how the runner
# splits lines. The old `contains("\n")` accepted both.
reject "carriage return in a value" '{"MSG":"harmless\rPATH=/tmp/evil"}'
reject "carriage return in a key" '{"MSG\rPATH=/tmp/evil":"x"}'

# CRLF contains an LF, so the old guard already rejected it. Kept as a regression
# test: it is the case a future rewrite of the expression is most likely to drop.
reject "CRLF in a value" '{"MSG":"harmless\r\nPATH=/tmp/evil"}'

# Invalid JSON already failed the step before the guard existed (`set -euo
# pipefail` plus a non-zero jq); it must keep failing rather than fall through.
reject "invalid JSON" 'not-json'

echo "PASS: ci-go.yml test-env-vars line-break guard"

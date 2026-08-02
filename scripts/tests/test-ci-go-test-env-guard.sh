#!/usr/bin/env bash
# $GITHUB_ENV is line-based, so a newline inside a `test-env-vars` value turns
# one entry into several — whoever controls that input can set PATH, GOFLAGS or
# LD_PRELOAD for every following step of the job, `go test` included. ci-go.yml
# rejects such values before writing the file; this checks the rejecting jq
# expression actually does that.
#
# The expression is read out of ci-go.yml rather than repeated here, so the two
# cannot drift: a guard edited in the workflow is the guard under test. Both
# jobs (test-and-lint, test-and-lint-postgres) carry it and both are checked.
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
[ "$COUNT" -eq 2 ] ||
  fail "expected the guard in both jobs, found $COUNT occurrence(s) in ci-go.yml"

# Both occurrences must be the same expression — one job hardened and the other
# left behind is the failure mode this repo already had.
[ "$(sort -u <<<"$GUARDS" | grep -c .)" -eq 1 ] ||
  fail "the two guards in ci-go.yml differ; they must be identical"

GUARD="$(head -n 1 <<<"$GUARDS")"

# accept <label> <json> — value has no newline, the step must proceed.
accept() {
  printf '%s' "$2" | jq -e "$GUARD" >/dev/null ||
    fail "guard rejects a legitimate input: $1"
}

# reject <label> <json> — value carries a newline, the step must stop.
reject() {
  if printf '%s' "$2" | jq -e "$GUARD" >/dev/null 2>&1; then
    fail "guard accepts an injecting input: $1"
  fi
}

accept "single-line entries" '{"API_URL":"http://localhost","MSG":"a b"}'
accept "empty object" '{}'
accept "non-string values" '{"PORT":5432,"DEBUG":true}'
accept "value containing a literal backslash-n" '{"MSG":"a\\nb"}'
reject "newline in a value" '{"MSG":"harmless\nPATH=/tmp/evil"}'
reject "newline in the second of two values" '{"API":"a b","MSG":"x\nGOFLAGS=-tags=evil"}'
reject "trailing newline in a value" '{"MSG":"value\n"}'

# A key carries the same injection: `{"A\nPATH=/tmp/evil":"x"}` renders as two
# lines, the second of which is a complete assignment.
reject "newline in a key" '{"MSG\nPATH=/tmp/evil":"x"}'
reject "newline in the second of two keys" '{"API":"a b","MSG\nLD_PRELOAD=/tmp/evil.so":"x"}'

# Invalid JSON already failed the step before the guard existed (`set -euo
# pipefail` plus a non-zero jq); it must keep failing rather than fall through.
reject "invalid JSON" 'not-json'

echo "PASS: ci-go.yml test-env-vars newline guard"

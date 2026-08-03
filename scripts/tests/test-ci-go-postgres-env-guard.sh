#!/usr/bin/env bash
# The `postgres-user`, `postgres-password` and `postgres-db` inputs are joined
# into the DATABASE_URL line that ci-go.yml writes to $GITHUB_ENV. That file is
# line-based, so a line break inside one of the three turns one entry into
# several and whoever controls the input can set PATH, GOFLAGS or LD_PRELOAD for
# every following step. ci-go.yml rejects such values before the write; this
# checks the rejecting loop actually does that, that it aborts rather than warns,
# and that it sits in the same step as the write it protects.
#
# The loop is read out of ci-go.yml rather than repeated here, so the two cannot
# drift: a guard edited in the workflow is the guard under test. This is the
# same arrangement as test-ci-go-test-env-guard.sh, which covers the
# `test-env-vars` guard in the same file.
#
# Run: scripts/tests/test-ci-go-postgres-env-guard.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORKFLOW="$REPO/.github/workflows/ci-go.yml"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# The guard is a `for` loop over the three variables wrapping an `if` that tests
# for a newline. Both lines are read from the workflow, so a rename or a changed
# test surfaces here rather than silently diverging.
# shellcheck disable=SC2016 # the $VAR text is matched literally in the YAML
FOR_LINE="$(sed -n 's/^ *\(for value in "\$POSTGRES_USER".*\); do$/\1/p' "$WORKFLOW")"
[ -n "$FOR_LINE" ] || fail "no postgres guard loop found in ci-go.yml"
[ "$(grep -c . <<<"$FOR_LINE")" -eq 1 ] ||
  fail "expected exactly one postgres guard loop in ci-go.yml"

# shellcheck disable=SC2016 # the $value text is matched literally in the YAML
IF_LINE="$(sed -n 's/^ *if \(\[ "\$value" != .*\]\); then$/\1/p' "$WORKFLOW")"
[ -n "$IF_LINE" ] || fail "no postgres guard newline test found in ci-go.yml"
[ "$(grep -c . <<<"$IF_LINE")" -eq 1 ] ||
  fail "expected exactly one postgres guard newline test in ci-go.yml"

# All three inputs must be covered — one hardened and another left behind is the
# failure mode this repo already had with the two test-env-vars occurrences.
for var in POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB; do
  case "$FOR_LINE" in
  *"\$$var"*) ;;
  *) fail "postgres guard does not cover \$$var" ;;
  esac
done

# The guard must sit above the write it protects, otherwise the injected line is
# already in $GITHUB_ENV by the time it runs. `|| true` on both greps: under
# `set -euo pipefail` a non-matching grep would abort the script at the
# assignment, so the drift this file exists to catch would surface as a bare
# non-zero exit instead of the diagnostic below.
# shellcheck disable=SC2016 # the $POSTGRES_USER text is matched literally
GUARD_LINE="$(grep -n 'for value in "\$POSTGRES_USER"' "$WORKFLOW" | cut -d: -f1 || true)"
[ -n "$GUARD_LINE" ] || fail "no postgres guard loop line found in ci-go.yml"
WRITE_LINE="$(grep -n "^ *printf 'DATABASE_URL=postgres" "$WORKFLOW" | cut -d: -f1 || true)"
[ -n "$WRITE_LINE" ] || fail "no DATABASE_URL write found in ci-go.yml"
[ "$(grep -c . <<<"$WRITE_LINE")" -eq 1 ] ||
  fail "expected exactly one DATABASE_URL write in ci-go.yml"
[ "$GUARD_LINE" -lt "$WRITE_LINE" ] ||
  fail "postgres guard is at line $GUARD_LINE, below the write at $WRITE_LINE"

# Above the write is not enough — both must be in the *same* step. A guard moved
# into any earlier step would still be "above" this write while leaving it
# unprotected, because each `run:` block is its own shell: the check would pass
# while the value reaching `printf` had never been tested.
if sed -n "${GUARD_LINE},${WRITE_LINE}p" "$WORKFLOW" | grep -q '^ *- name:'; then
  fail "postgres guard and the DATABASE_URL write are in different steps"
fi

# The guard must abort, not just detect. Without this, turning the `exit 1` into
# a warning would leave every other assertion here green and the injection open.
sed -n "${GUARD_LINE},$((WRITE_LINE - 1))p" "$WORKFLOW" | grep -q '^ *exit 1$' ||
  fail "postgres guard does not exit on a rejected value"

# The newline test itself, exercised against real values. The condition comes
# from the workflow via $IF_LINE, so the behaviour under test is the shipped one.
# `eval` on a line just read from a tracked file in this repo, not on input.
run_guard() {
  local value
  # shellcheck disable=SC2034 # $value is read by the guard inside the eval below
  for value in "$1" "$2" "$3"; do
    if eval "$IF_LINE"; then
      return 1
    fi
  done
  return 0
}

# accept <label> <user> <password> <db> — no newline, the step must proceed.
accept() {
  local label="$1"
  shift
  run_guard "$@" || fail "guard rejects a legitimate input: $label"
}

# reject <label> <user> <password> <db> — a newline, the step must stop.
reject() {
  local label="$1"
  shift
  if run_guard "$@"; then
    fail "guard accepts an injecting input: $label"
  fi
}

# "x", newline, "y" — command substitution strips trailing newlines, not inner.
NL="$(printf 'x\ny')"

accept "workflow defaults" postgres postgres testdb
accept "empty values" "" "" ""
accept "values with spaces and shell metacharacters" "us er" 'p@ss=w#rd$`' 'test db'
accept "value containing a literal backslash-n" 'a\nb' 'c\nd' 'e\nf'
accept "value containing a tab" "$(printf 'a\tb')" postgres testdb

reject "newline in postgres-user" "$NL" postgres testdb
reject "newline in postgres-password" postgres "$NL" testdb
reject "newline in postgres-db" postgres postgres "$NL"
reject "newline carrying a complete assignment" \
  postgres "$(printf 'pw\nPATH=/tmp/evil')" testdb
reject "newline in all three" "$NL" "$NL" "$NL"
reject "carriage return in postgres-user" "$(printf 'a\rPATH=/tmp/evil')" postgres testdb
reject "carriage return in postgres-password" postgres "$(printf 'a\rb')" testdb
reject "CRLF in postgres-db" postgres postgres "$(printf 'a\r\nb')"
# Not tested: a value that is only a trailing newline. Command substitution
# strips those, so it cannot be constructed here — and the injection needs a
# following assignment anyway, which "newline carrying a complete assignment"
# above covers.

echo "PASS: ci-go.yml postgres newline guard"

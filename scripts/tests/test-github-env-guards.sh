#!/usr/bin/env bash
# release-go.yml and deploy-terraform.yml both write caller-controlled values to
# $GITHUB_ENV. That file is line-based, so an unguarded write lets whoever
# controls the input add entries — PATH, GOFLAGS, LD_PRELOAD — for every
# following step of the job. Both now reject such values before the write; this
# checks the guards do that, that they abort rather than warn, and that each one
# sits in the same step as the write it protects.
#
# The guards are read out of the workflows rather than repeated here, so the two
# cannot drift: a guard edited in the workflow is the guard under test. Same
# arrangement as test-ci-go-postgres-env-guard.sh and
# test-ci-go-test-env-guard.sh, which cover the two ci-go.yml guards this
# pattern comes from.
#
# The two sinks take different shapes on purpose. `extra-env` in release-go.yml
# is a documented multi-line KEY=VALUE list, so its own newlines are separators
# and a blanket LF reject would break the input's contract — it validates each
# line as an assignment instead. The deploy-terraform.yml values are single
# values, so the per-value LF/CR reject from ci-go.yml applies unchanged.
#
# Run: scripts/tests/test-github-env-guards.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
RELEASE_GO="$REPO/.github/workflows/release-go.yml"
DEPLOY_TF="$REPO/.github/workflows/deploy-terraform.yml"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# guard_above_write <file> <guard-grep> <write-grep> <label>
#
# Asserts the guard exists exactly once, sits above the write, shares the write's
# step, and exits on rejection. `|| true` on the greps: under `set -euo pipefail`
# a non-matching grep would abort at the assignment, so the drift this file
# exists to catch would surface as a bare non-zero exit instead of a diagnostic.
guard_above_write() {
  local file="$1" guard_re="$2" write_re="$3" label="$4"
  local guard_line write_line

  guard_line="$(grep -n "$guard_re" "$file" | cut -d: -f1 || true)"
  [ -n "$guard_line" ] || fail "no $label guard found"
  [ "$(grep -c . <<<"$guard_line")" -eq 1 ] ||
    fail "expected exactly one $label guard"

  write_line="$(grep -n "$write_re" "$file" | cut -d: -f1 || true)"
  [ -n "$write_line" ] || fail "no $label write found"
  [ "$(grep -c . <<<"$write_line")" -eq 1 ] ||
    fail "expected exactly one $label write"

  [ "$guard_line" -lt "$write_line" ] ||
    fail "$label guard is at line $guard_line, below the write at $write_line"

  # Above the write is not enough — both must be in the *same* step. A guard
  # moved into an earlier step would still be "above" this write while leaving
  # it unprotected, because each `run:` block is its own shell.
  if sed -n "${guard_line},${write_line}p" "$file" | grep -q '^ *- name:'; then
    fail "$label guard and its write are in different steps"
  fi

  # The guard must abort, not just detect. Counting rather than grepping for one
  # `exit 1`: a guard with several rejection paths would keep a bare `grep -q`
  # green while one of them was downgraded to a warning. Every `Error:` the
  # guard prints must be followed by an abort, so the two counts have to match.
  local errors exits
  errors="$(sed -n "${guard_line},$((write_line - 1))p" "$file" |
    grep -c '^ *echo "Error:' || true)"
  exits="$(sed -n "${guard_line},$((write_line - 1))p" "$file" |
    grep -c '^ *exit 1$' || true)"
  [ "$errors" -gt 0 ] || fail "$label guard reports no rejection"
  [ "$exits" -eq "$errors" ] ||
    fail "$label guard reports $errors rejections but aborts on only $exits"
}

# --- release-go.yml: extra-env is a multi-line KEY=VALUE list ----------------

# shellcheck disable=SC2016 # the $EXTRA_ENV text is matched literally in the YAML
guard_above_write "$RELEASE_GO" \
  '^ *while IFS= read -r line; do$' \
  '^ *echo "\$EXTRA_ENV" >> "\$GITHUB_ENV"$' \
  'extra-env'

# The assignment test is read from the workflow, so the behaviour exercised
# below is the shipped one. `eval` on lines just read from a tracked file in
# this repo, not on input.
CASE_PATTERN="$(sed -n 's/^ *\(\[A-Za-z_\]\*=\*\))$/\1/p' "$RELEASE_GO")"
[ -n "$CASE_PATTERN" ] || fail "no extra-env assignment pattern found"
[ "$(grep -c . <<<"$CASE_PATTERN")" -eq 1 ] ||
  fail "expected exactly one extra-env assignment pattern"

# shellcheck disable=SC2016 # the $line text is matched literally in the YAML
CR_LINE="$(sed -n 's/^ *if \(\[ "\$line" != .*\]\); then$/\1/p' "$RELEASE_GO")"
[ -n "$CR_LINE" ] || fail "no extra-env CR test found"

# shellcheck disable=SC2016 # the $name text is matched literally in the YAML
NAME_LINE="$(sed -n 's/^ *if \(\[ "\$name" != .*\]\); then$/\1/p' "$RELEASE_GO")"
[ -n "$NAME_LINE" ] || fail "no extra-env identifier test found"

# Replays the workflow's per-line loop using the conditions read above.
# Returns 0 when every line is accepted, 1 when one is rejected.
run_extra_env_guard() {
  local line name
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if eval "$CR_LINE"; then
      return 1
    fi
    # shellcheck disable=SC2254 # $CASE_PATTERN is the workflow's glob, by design
    case "$line" in
    $CASE_PATTERN)
      # shellcheck disable=SC2034 # $name is read by the guard inside the eval
      name=${line%%=*}
      if eval "$NAME_LINE"; then
        return 1
      fi
      ;;
    *)
      return 1
      ;;
    esac
  done <<<"$1"
  return 0
}

accept_env() {
  run_extra_env_guard "$2" || fail "extra-env guard rejects a legitimate input: $1"
}

reject_env() {
  if run_extra_env_guard "$2"; then
    fail "extra-env guard accepts an injecting input: $1"
  fi
}

accept_env "single assignment" 'CGO_ENABLED=0'
accept_env "multiple assignments" "$(printf 'CGO_ENABLED=0\nGOOS=linux')"
accept_env "blank line between assignments" "$(printf 'A=1\n\nB=2')"
accept_env "underscore-prefixed name" '_PRIVATE=1'
accept_env "digits in name" 'GO111MODULE=on'
accept_env "empty value" 'EMPTY='
accept_env "value containing an equals sign" 'FLAGS=-X=main.version=1.2.3'
accept_env "value with spaces and shell metacharacters" 'ARGS=a b $`|;&'
accept_env "value containing a literal backslash-n" 'LITERAL=a\nb'
accept_env "value containing a tab" "$(printf 'TABBED=a\tb')"

reject_env "line without an equals sign" 'PATH /tmp/evil'
reject_env "second line without an equals sign" "$(printf 'A=1\nnot an assignment')"
reject_env "name starting with a digit" '1BAD=x'
reject_env "name containing a space" 'BAD NAME=x'
# shellcheck disable=SC2016 # the metacharacters are the test value, unexpanded
reject_env "name containing a shell metacharacter" 'BAD$NAME=x'
reject_env "leading equals sign" '=orphan'
reject_env "carriage return in a value" "$(printf 'A=a\rPATH=/tmp/evil')"
reject_env "CRLF between assignments" "$(printf 'A=1\r\nB=2')"

# --- deploy-terraform.yml: single values, per-value LF/CR reject -------------

# shellcheck disable=SC2016 # the $R2_ACCESS_KEY text is matched literally
guard_above_write "$DEPLOY_TF" \
  '^ *for value in "\$R2_ACCESS_KEY"' \
  '^ *} >> "\$GITHUB_ENV"$' \
  'R2 credential'

# The mapping guard shares its condition with the R2 loop above, so the grep
# anchors on the `$dst` message that only the mapping one carries — matching the
# bare condition would find both and the count assertion would trip.
# shellcheck disable=SC2016 # the $dst text is matched literally in the YAML
guard_above_write "$DEPLOY_TF" \
  '^ *echo "Error: multi-line value for \$dst is not supported" >&2$' \
  '^ *\[ -n "\$value" \] && echo "\$dst=\$value" >> "\$GITHUB_ENV"$' \
  'env-mapping value'

# All three credentials must be covered — one hardened and another left behind
# is the failure mode this repo already had with the two test-env-vars
# occurrences.
# shellcheck disable=SC2016 # the $VAR text is matched literally in the YAML
TF_FOR_LINE="$(sed -n 's/^ *\(for value in "\$R2_ACCESS_KEY".*\); do$/\1/p' "$DEPLOY_TF")"
[ -n "$TF_FOR_LINE" ] || fail "no R2 credential guard loop found"
for var in R2_ACCESS_KEY R2_SECRET_KEY BW_TOKEN; do
  case "$TF_FOR_LINE" in
  *"\$$var"*) ;;
  *) fail "R2 credential guard does not cover \$$var" ;;
  esac
done

# The value test, exercised against real values. Both deploy-terraform.yml
# guards use the same condition, so one extraction covers both.
# shellcheck disable=SC2016 # the $value text is matched literally in the YAML
TF_IF_LINE="$(sed -n 's/^ *if \(\[ "\$value" != .*\]\); then$/\1/p' "$DEPLOY_TF" | head -1)"
[ -n "$TF_IF_LINE" ] || fail "no deploy-terraform value test found"

run_value_guard() {
  local value
  # shellcheck disable=SC2034 # $value is read by the guard inside the eval
  for value in "$@"; do
    if eval "$TF_IF_LINE"; then
      return 1
    fi
  done
  return 0
}

accept_value() {
  local label="$1"
  shift
  run_value_guard "$@" || fail "value guard rejects a legitimate input: $label"
}

reject_value() {
  local label="$1"
  shift
  if run_value_guard "$@"; then
    fail "value guard accepts an injecting input: $label"
  fi
}

# "x", newline, "y" — command substitution strips trailing newlines, not inner.
NL="$(printf 'x\ny')"

accept_value "typical credentials" 'AKIAEXAMPLE' 'c2VjcmV0+key/value=' 'bws-token'
accept_value "empty values" "" "" ""
# shellcheck disable=SC2016 # the metacharacters are the test values, unexpanded
accept_value "values with shell metacharacters" 'a$(id)' 'b`id`' 'c;d'
accept_value "value containing a literal backslash-n" 'a\nb' 'c\nd' 'e\nf'

reject_value "newline in the access key" "$NL" secret token
reject_value "newline in the secret key" key "$NL" token
reject_value "newline in the Bitwarden token" key secret "$NL"
reject_value "newline carrying a complete assignment" \
  key "$(printf 'sec\nPATH=/tmp/evil')" token
reject_value "carriage return in the access key" "$(printf 'a\rPATH=/tmp/evil')" secret token
reject_value "CRLF in the Bitwarden token" key secret "$(printf 'a\r\nb')"

# The identifier check on the mapping target. `xargs` strips whitespace but
# passes through a name that is not an identifier.
# shellcheck disable=SC2016 # the $dst text is matched literally in the YAML
DST_LINE="$(sed -n 's/^ *if \(\[ -z "\$dst" \].*\); then$/\1/p' "$DEPLOY_TF")"
[ -n "$DST_LINE" ] || fail "no env-mapping target identifier test found"

run_dst_guard() {
  # shellcheck disable=SC2034 # $dst is read by the guard inside the eval below
  local dst="$1"
  if eval "$DST_LINE"; then
    return 1
  fi
  return 0
}

run_dst_guard 'TF_VAR_token' || fail "target guard rejects a legitimate name"
run_dst_guard 'A1_b2' || fail "target guard rejects a legitimate name with digits"
run_dst_guard '' && fail "target guard accepts an empty name"
run_dst_guard 'BAD NAME' && fail "target guard accepts a name with a space"
run_dst_guard 'BAD-NAME' && fail "target guard accepts a name with a dash"
# shellcheck disable=SC2016 # the metacharacter is the test value, unexpanded
run_dst_guard 'BAD$NAME' && fail "target guard accepts a name with a metacharacter"

echo "PASS: release-go.yml and deploy-terraform.yml \$GITHUB_ENV guards"

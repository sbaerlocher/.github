#!/usr/bin/env bash
# release-go.yml and deploy-terraform.yml both write caller-controlled values to
# $GITHUB_ENV. That file is line-based, so an unguarded write lets whoever
# controls the input add entries — PATH, GOFLAGS, LD_PRELOAD — for every
# following step of the job. Both now reject such values before the write; this
# checks the guards do that, that they abort rather than warn, and that each one
# sits in the same step as the write it protects.
#
# The guards are read out of the workflows rather than repeated here, so the two
# cannot drift. Two kinds of extraction do that, and they guarantee different
# things. Where the condition is matched by shape (the `$value` and `$line`
# tests), the edited guard is the guard under test. Where the pattern is matched
# by its literal text (the case-arm globs, the identifier test), an edit makes
# this file fail loudly instead — no change to a guard can land without the test
# being updated alongside it. Both are fail-closed; neither lets a weakened
# guard pass silently, which is the property that matters. Same arrangement as
# test-ci-go-postgres-env-guard.sh and test-ci-go-test-env-guard.sh, which cover
# the two ci-go.yml guards this pattern comes from.
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
# Both forms share one case arm, so each glob is taken from that line: the
# delimiter one before the `|`, the assignment one after it. Matching arm order
# is what the workflow must *not* do (see the comment there), so the test does
# not encode an order either.
ARM_LINE="$(sed -n "s/^ *\(\[A-Za-z_\]\*'<<'\* | \[A-Za-z_\]\*=\*\))$/\1/p" "$RELEASE_GO")"
[ -n "$ARM_LINE" ] || fail "no extra-env case arm found"
[ "$(grep -c . <<<"$ARM_LINE")" -eq 1 ] || fail "expected exactly one extra-env case arm"

CASE_PATTERN="${ARM_LINE##* | }"
[ -n "$CASE_PATTERN" ] || fail "no extra-env assignment pattern found"

# shellcheck disable=SC2016 # the $line text is matched literally in the YAML
CR_LINE="$(sed -n 's/^ *if \(\[ "\$line" != .*\]\); then$/\1/p' "$RELEASE_GO")"
[ -n "$CR_LINE" ] || fail "no extra-env CR test found"

# One shared identifier test covers both forms. The count is asserted rather
# than assumed: a second, differently-spelled copy would mean `head -1` silently
# replayed one form's check for both.
# shellcheck disable=SC2016 # the $name text is matched literally in the YAML
NAME_LINE="$(sed -n 's/^ *if \(\[ "\$name" != "\${name\/\/\[^A-Za-z0-9_\]\/}" \]\).*; then$/\1/p' \
  "$RELEASE_GO")"
[ -n "$NAME_LINE" ] || fail "no extra-env identifier test found"
[ "$(grep -c . <<<"$NAME_LINE")" -eq 1 ] ||
  fail "expected exactly one extra-env identifier test"

# The empty-delimiter case gets its own message: reporting it as an invalid
# identifier would name the one part of `A<<` that is actually valid.
grep -q '^ *echo "Error: extra-env delimiter block has an empty delimiter" >&2$' "$RELEASE_GO" ||
  fail "no extra-env empty-delimiter message found"

# The inner dispatch must decide by position, not by arm order — an arm-order
# dispatch sends `CGO_CFLAGS=-DSHIFT=1<<3` down the delimiter path. Both the
# subject it switches on and its assignment arm are read from the workflow, so
# replacing that dispatch surfaces here instead of silently replaying the old
# shape. The accept cases below then exercise the extracted logic.
# shellcheck disable=SC2016 # the ${line%%<<*} text is matched literally
DISPATCH_SUBJECT="$(sed -n 's/^ *case "\(\${line%%<<\*}\)" in$/\1/p' "$RELEASE_GO")"
[ -n "$DISPATCH_SUBJECT" ] ||
  fail "extra-env dispatch does not switch on the text before the delimiter"
# shellcheck disable=SC2016 # the $line text is matched literally in the YAML
DISPATCH_ARM="$(sed -n 's/^ *\("\$line" | \*=\*\))$/\1/p' "$RELEASE_GO")"
[ -n "$DISPATCH_ARM" ] || fail "extra-env dispatch has no assignment-first arm"

# The delimiter glob, so the documented `NAME<<EOF` form stays covered here too.
# The workflow quotes `<<` inside the glob; the quotes only make it literal,
# which it already is in a pattern, so they are dropped for the replay below —
# left in, `case` would match them as characters and every block would fail.
DELIM_PATTERN="$(tr -d "'" <<<"${ARM_LINE%% | *}")"
[ -n "$DELIM_PATTERN" ] || fail "no extra-env delimiter pattern found"

# An unterminated block must be rejected after the loop. The replay below models
# that, so the assertion has to come from the workflow — otherwise dropping the
# workflow's check would leave the replay's own copy green.
# The same `[ -n "$delim" ]` test also guards the in-loop body skip, so the
# check is located by its error message and then verified to be a real test
# followed by an abort — grepping the bare condition would match the in-loop
# one and stay green while the post-loop check was disabled.
# shellcheck disable=SC2016 # the $delim text is matched literally in the YAML
UNTERM_LINE="$(grep -n '^ *echo "Error: extra-env has an unterminated \$delim block" >&2$' \
  "$RELEASE_GO" | cut -d: -f1 || true)"
[ -n "$UNTERM_LINE" ] || fail "no extra-env unterminated-block check found"
[ "$(grep -c . <<<"$UNTERM_LINE")" -eq 1 ] ||
  fail "expected exactly one extra-env unterminated-block check"
# shellcheck disable=SC2016 # the $delim text is matched literally in the YAML
sed -n "$((UNTERM_LINE - 1))p" "$RELEASE_GO" | grep -q '^ *if \[ -n "\$delim" \]; then$' ||
  fail "extra-env unterminated-block check is not guarded by a delim test"
sed -n "$((UNTERM_LINE + 1))p" "$RELEASE_GO" | grep -q '^ *exit 1$' ||
  fail "extra-env unterminated-block check does not abort"

# Replays the workflow's per-line loop using the conditions read above.
# Returns 0 when every line is accepted, 1 when one is rejected.
run_extra_env_guard() {
  # shellcheck disable=SC2034 # $name is read by the guard inside the eval below
  local line name delim=''
  while IFS= read -r line; do
    if eval "$CR_LINE"; then
      return 1
    fi
    if [ -n "$delim" ]; then
      [ "$line" = "$delim" ] && delim=''
      continue
    fi
    [ -z "$line" ] && continue
    # shellcheck disable=SC2254 # the patterns are the workflow's globs, by design
    case "$line" in
    $DELIM_PATTERN | $CASE_PATTERN)
      # Position decides the form, not arm order. Subject and assignment arm
      # come from the workflow via `eval`, so swapping the workflow's dispatch
      # for an arm-order one changes what runs here too.
      local is_block=0
      eval "case \"$DISPATCH_SUBJECT\" in
      $DISPATCH_ARM)
        name=\${line%%=*}
        ;;
      *)
        name=\${line%%<<*}
        delim=\${line#*<<}
        is_block=1
        ;;
      esac"
      # An empty delimiter (`A<<`) is rejected, matching the workflow's own arm.
      [ "$is_block" -eq 1 ] && [ -z "$delim" ] && return 1
      if eval "$NAME_LINE"; then
        return 1
      fi
      ;;
    *)
      return 1
      ;;
    esac
  done <<<"$1"
  # An unterminated block is rejected, matching the check after the loop.
  [ -z "$delim" ]
}

accept_env() {
  run_extra_env_guard "$2" || fail "extra-env guard rejects a legitimate input: $1"
}

reject_env() {
  if run_extra_env_guard "$2"; then
    fail "extra-env guard accepts an injecting input: $1"
  fi
}

# Positive controls on the two extracted globs before they are relied on: a
# capture that grabbed the wrong text would match nothing, and every reject case
# below would then pass vacuously.
# shellcheck disable=SC2254,SC2194 # workflow glob; the constant is the control
case 'A=1' in $CASE_PATTERN) ;; *) fail "extra-env assignment pattern extracted wrong" ;; esac
# shellcheck disable=SC2254,SC2194 # workflow glob; the constant is the control
case 'A<<EOF' in $DELIM_PATTERN) ;; *) fail "extra-env delimiter pattern extracted wrong" ;; esac

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
# `=` before `<<` means the line is an assignment whose value happens to contain
# `<<` — a shift expression in a compile flag is not exotic for a Go release.
accept_env "value containing a shift expression" 'CGO_CFLAGS=-DSHIFT=1<<3'
accept_env "value containing a bare <<" 'LDFLAGS=-X main.note=a<<b'
accept_env "shift expression after a delimiter block" \
  "$(printf 'A<<EOF\nx\nEOF\nCGO_CFLAGS=-DSHIFT=1<<3')"
# The delimiter form documented for $GITHUB_ENV — the reason a blanket
# "every line is an assignment" rule would have been a breaking change.
accept_env "delimiter block" "$(printf 'JSON_CONFIG<<EOF\n{"a": 1}\nEOF')"
accept_env "delimiter block with a blank body line" \
  "$(printf 'LDFLAGS<<EOF\n-X main.a=1\n\n-X main.b=2\nEOF')"
accept_env "delimiter body that looks like garbage" \
  "$(printf 'BLOB<<EOF\nnot an assignment\n  indented\nEOF')"
accept_env "assignment after a closed delimiter block" \
  "$(printf 'A<<EOF\nbody\nEOF\nB=2')"
accept_env "two delimiter blocks" \
  "$(printf 'A<<EOF\nx\nEOF\nB<<END\ny\nEND')"

reject_env "line without an equals sign" 'PATH /tmp/evil'
reject_env "second line without an equals sign" "$(printf 'A=1\nnot an assignment')"
reject_env "name starting with a digit" '1BAD=x'
reject_env "name containing a space" 'BAD NAME=x'
# shellcheck disable=SC2016 # the metacharacters are the test value, unexpanded
reject_env "name containing a shell metacharacter" 'BAD$NAME=x'
reject_env "leading equals sign" '=orphan'
reject_env "carriage return in a value" "$(printf 'A=a\rPATH=/tmp/evil')"
reject_env "CRLF between assignments" "$(printf 'A=1\r\nB=2')"
reject_env "unterminated delimiter block" "$(printf 'A<<EOF\nbody')"
reject_env "delimiter block with an empty delimiter" "$(printf 'A<<\nbody')"
reject_env "delimiter name that is not an identifier" "$(printf 'BAD NAME<<EOF\nx\nEOF')"
reject_env "garbage after a closed delimiter block" \
  "$(printf 'A<<EOF\nbody\nEOF\nnot an assignment')"
reject_env "CR inside a delimiter body" "$(printf 'A<<EOF\nx\ry\nEOF')"

# --- deploy-terraform.yml: single values, per-value LF/CR reject -------------

# shellcheck disable=SC2016 # the $R2_ACCESS_KEY text is matched literally
guard_above_write "$DEPLOY_TF" \
  '^ *for value in "\$R2_ACCESS_KEY"' \
  '^ *} >> "\$GITHUB_ENV"$' \
  'R2 credential'

# The mapping guard shares its condition with the R2 loop above, so the grep
# anchors on the name loop that only the mapping one carries — matching the bare
# condition would find both and the count assertion would trip.
# shellcheck disable=SC2016 # the $src text is matched literally in the YAML
guard_above_write "$DEPLOY_TF" \
  '^ *for name in "\$src" "\$dst"; do$' \
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

# The identifier check on both mapping names. `xargs` strips whitespace but does
# not expand, so a name reaches the loop intact — and bash evaluates an array
# subscript inside `${!src}` as an arithmetic expression, which performs command
# substitution. Both names must therefore be checked, and checked *before* the
# expansion; a guard that only covered `dst`, or that ran after `value=`, would
# leave that path open.
# The reject arm is read whole and replayed via `eval`, not substituted into a
# `case` as a variable: an expanded variable's `|` is not a pattern separator,
# so an alternation would collapse into one literal pattern and match nothing.
NAME_PATTERN="$(sed -n "s/^ *\('' | \[0-9\]\* | \*\[!A-Za-z0-9_\]\*\))$/\1/p" "$DEPLOY_TF")"
[ -n "$NAME_PATTERN" ] || fail "no env-mapping name reject pattern found"
[ "$(grep -c . <<<"$NAME_PATTERN")" -eq 1 ] ||
  fail "expected exactly one env-mapping name reject pattern"

# shellcheck disable=SC2016 # the $src text is matched literally in the YAML
NAME_LOOP="$(grep -n '^ *for name in "\$src" "\$dst"; do$' "$DEPLOY_TF" | cut -d: -f1 || true)"
[ -n "$NAME_LOOP" ] || fail "no env-mapping name guard covering both names found"

# shellcheck disable=SC2016 # the ${!src} text is matched literally in the YAML
EXPANSION="$(grep -n '^ *value="\${!src}"$' "$DEPLOY_TF" | cut -d: -f1 || true)"
[ -n "$EXPANSION" ] || fail "no env-mapping indirect expansion found"
[ "$NAME_LOOP" -lt "$EXPANSION" ] ||
  fail "env-mapping name guard is at line $NAME_LOOP, below the expansion at $EXPANSION"

# Returns 0 when the name is accepted, 1 when the workflow's arm rejects it.
# `eval` on a pattern just read from a tracked file in this repo, not on input.
run_name_guard() {
  # shellcheck disable=SC2034 # $name is read by the case inside the eval below
  local name="$1" rejected=1
  eval "case \"\$name\" in
  $NAME_PATTERN) rejected=0 ;;
  esac"
  [ "$rejected" -eq 1 ]
}

# Guard the extraction itself: a capture that swallowed the wrong `)` would
# yield a pattern matching nothing, and every reject case below would pass
# vacuously while only the accept cases failed.
run_name_guard 'Ab' || fail "env-mapping name pattern extracted wrong: [$NAME_PATTERN]"
run_name_guard 'X' || fail "name guard rejects a single-character name"

run_name_guard 'TF_VAR_token' || fail "name guard rejects a legitimate name"
run_name_guard 'A1_b2' || fail "name guard rejects a legitimate name with digits"
run_name_guard '' && fail "name guard accepts an empty name"
run_name_guard 'BAD NAME' && fail "name guard accepts a name with a space"
run_name_guard 'BAD-NAME' && fail "name guard accepts a name with a dash"
run_name_guard '1LEADING' && fail "name guard accepts a name starting with a digit"
# The indirect-expansion payload the name guard exists to stop.
# shellcheck disable=SC2016 # the subscript is the test value, unexpanded
run_name_guard 'x[$(id)]' && fail "name guard accepts an array-subscript payload"

echo "PASS: release-go.yml and deploy-terraform.yml \$GITHUB_ENV guards"

#!/usr/bin/env bash
# A `${{ inputs.* }}` reference inside a `run:` body is substituted as text
# before the shell parses the line, so a caller-supplied value can close a quote
# or open a `$(...)` and run as code on the runner. In an *unquoted* heredoc
# (`<< EOF`) the body is expanded too, so a value reaching a step summary that
# way executes as well.
#
# Reusable workflows pass such values through `env:` and reference them as shell
# variables. This asserts that holds: no interpolated caller-controlled value
# left in a `run:` body — block-scalar, folded or single-line — and no unquoted
# heredoc delimiter. It is a structural check on the YAML, so a regression fails
# here rather than on a runner.
#
# The checked set is *derived* from the `workflow_call` trigger, not maintained
# as a list. An allow-list inverts the guard: a workflow absent from it is
# unchecked by default, and the reason for its absence tends to be the very
# defect the guard exists to catch (PR #299 — two workflows sat outside the list
# exactly as long as they were unsafe). Deriving it means a new reusable
# workflow is covered the day it lands.
#
# A value that merely *travels* through `env:` is not automatically safe: it can
# leave a step again as a workflow-level output and be interpolated downstream,
# which is why `security-code.yml` also constrains `package-manager` to a known
# set before writing it to `$GITHUB_OUTPUT`.
#
# Run: scripts/tests/test-workflow-input-injection.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORKFLOWS="$REPO/.github/workflows"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# Workflows exempt from rule 2 only, each with the reason inline. An exception is
# a deliberate, argued carve-out — not a parking space for an unreviewed
# workflow. Both entries below build a heredoc body out of values that already
# arrived via `env:`; the expansion is the point, so quoting the delimiter would
# break them, and rule 2 has no way to tell that apart from the unsafe case.
#
# The exemption stops there. Rule 1 still runs on these files: it is the primary
# injection class, has nothing to do with heredoc quoting, and these two are the
# worst files to leave unchecked — their bodies already expand, so a substituted
# `$(...)` would execute rather than merely mis-parse.
HEREDOC_EXCEPTIONS=(
  ops-drift-issue.yml      # issue body + delta comment expand env-passed values
  ops-terraform-report.yml # deployment-metadata.json expands env-passed values
)

# The reusable set, derived from the `workflow_call` trigger. The classifier is
# shared with scripts/tests/test-workflow-counts.sh so the set scanned here and
# the counts stated in the docs cannot drift apart. Command substitution, not a
# process substitution: `done < <(...)` would not propagate the classifier's exit
# status, so a parse error would yield a silently shortened set and a green run.
REUSABLE="$("$REPO/scripts/list-reusable-workflows.sh" "$WORKFLOWS" --reusable)" ||
  fail "could not classify the workflow files"

REUSABLE_FILES=()
while IFS= read -r name; do
  [ -n "$name" ] || continue
  REUSABLE_FILES+=("$name")
done <<<"$REUSABLE"

[ ${#REUSABLE_FILES[@]} -gt 0 ] || fail "no reusable workflows found in $WORKFLOWS"

# An exception outlives its reason in two ways, and both read as "reviewed" while
# protecting nothing. `${arr[@]+…}` guards the empty case: bash 3.2, which macOS
# still ships as /bin/bash, treats an empty array as unset under `set -u`, and an
# empty array is the intended end state here.
for exc in ${HEREDOC_EXCEPTIONS[@]+"${HEREDOC_EXCEPTIONS[@]}"}; do
  # 1 — the file is gone, or no longer reusable.
  found=0
  for wf in "${REUSABLE_FILES[@]}"; do
    [ "$wf" = "$exc" ] && found=1 && break
  done
  [ "$found" -eq 1 ] ||
    fail "HEREDOC_EXCEPTIONS lists '$exc', which is not a reusable workflow — drop the entry"

  # 2 — the heredocs got quoted, so the carve-out is no longer buying anything.
  #     This makes the array self-emptying as the files are fixed.
  grep -qE '<<-?[[:space:]]*[A-Za-z_][A-Za-z0-9_]*([[:space:]]|$)' "$WORKFLOWS/$exc" ||
    fail "HEREDOC_EXCEPTIONS lists '$exc', which no longer has an unquoted heredoc — drop the entry"
done

# Print every line inside a `run:` body, as "<line-number>:<text>".
# Block scalars (`run: |`, `run: >`) open a block; a single-line `run: cmd` is a
# body of its own and must be scanned too — missing those hides real sinks.
run_block_lines() {
  awk '
    # Block scalar (| or >, with any modifier) or an empty value: opens a block.
    # run_indent is the column of the `run` key itself, not of a leading list
    # dash — a line level with the key is a sibling, not part of the body.
    /^[[:space:]]*-?[[:space:]]*run:[[:space:]]*[|>]/ ||
    /^[[:space:]]*-?[[:space:]]*run:[[:space:]]*$/ {
      line = $0
      sub(/run:.*$/, "", line)
      # +1 so this is the 1-based column of the `run` key, comparable to the
      # RSTART below: a sibling key sits at exactly this column.
      run_indent = length(line) + 1
      in_run = 1
      next
    }
    # Single-line body: `run: <command>`. Scan the line, open nothing.
    /^[[:space:]]*-?[[:space:]]*run:[[:space:]]*[^|>[:space:]]/ {
      in_run = 0
      print FNR ":" $0
      next
    }
    in_run {
      # A non-blank line at or left of the run: key ends the block. A comment
      # counts: at that indentation it belongs to the step, not to the script,
      # so treating it as body would swallow every following key.
      if ($0 ~ /[^[:space:]]/) {
        match($0, /[^ ]/)
        if (RSTART <= run_indent) {
          in_run = 0
          next
        }
      }
      print FNR ":" $0
    }
  ' "$1"
}

for wf in "${REUSABLE_FILES[@]}"; do
  heredoc_exempt=0
  for exc in ${HEREDOC_EXCEPTIONS[@]+"${HEREDOC_EXCEPTIONS[@]}"}; do
    [ "$wf" = "$exc" ] && heredoc_exempt=1 && break
  done

  path="$WORKFLOWS/$wf"

  # 1. No caller-controlled value interpolated into a shell body. `inputs.*` is
  #    the class this migration closed; `secrets.*` and `github.event.*` are the
  #    same mechanic, so they are held to the same rule rather than left for a
  #    later regression to introduce quietly.
  #    A step output (`steps.*.outputs.*`) is only as safe as what wrote it, so
  #    exempting it wholesale would reopen the hole — see the allow-list in
  #    security-code.yml's package-manager detection.
  # shellcheck disable=SC2016  # '${{' is the literal string being searched for
  hits="$(run_block_lines "$path" | grep -F '${{' |
    grep -E 'inputs\.|secrets\.|github\.event\.' || true)"
  if [ -n "$hits" ]; then
    echo "$hits" >&2
    fail "$wf interpolates a caller-controlled value inside a run: body"
  fi

  # 2. No unquoted heredoc delimiter: its body would expand a substituted value.
  #    `<< 'EOF'` and `<< "EOF"` are fine; a bare word is not, whatever it is
  #    called. `<<-` strips tabs but still expands, and the delimiter may be
  #    followed by a redirect (`cat <<EOF >"$f"`), so match the word itself
  #    rather than requiring it at end of line.
  #    Skipped only for the argued carve-outs above, where the expansion is the
  #    intent and every value in the body reached the shell through `env:`.
  if [ "$heredoc_exempt" -eq 0 ]; then
    heredocs="$(grep -nE '<<-?[[:space:]]*[A-Za-z_][A-Za-z0-9_]*([[:space:]]|$)' "$path" || true)"
    if [ -n "$heredocs" ]; then
      echo "$heredocs" >&2
      fail "$wf has an unquoted heredoc delimiter; quote it, e.g. << 'EOF'"
    fi
  fi
done

# The check above only proves absence. This proves the replacement behaves:
# a value carrying $(...) must be written literally, not executed.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
marker="$tmp/executed"
summary="$tmp/summary.md"

# Mirrors the migrated pattern: value via the environment, substituted by printf.
# The single-quoted script body keeps the backtick and the $(...) literal here;
# only the runner-side printf gets to see them, exactly as in the workflows.
IMAGE_REF="ghcr.io/org/app:\$(touch '$marker')" \
  bash -c 'printf "**Image:** \`%s\`\n" "$IMAGE_REF" >"$1"' _ "$summary"

[ ! -e "$marker" ] ||
  fail "the env:+printf pattern executed a \$(...) value instead of quoting it"
# shellcheck disable=SC2016  # the literal '$(touch' must survive into the file
grep -qF '$(touch' "$summary" ||
  fail "the env:+printf pattern dropped the literal value from the summary"

echo "PASS: workflow inputs reach run: blocks via env: (${#REUSABLE_FILES[@]} reusable workflows, ${#HEREDOC_EXCEPTIONS[@]} heredoc-exempt)"

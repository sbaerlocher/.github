#!/usr/bin/env bash
# A `${{ inputs.* }}` reference inside a `run:` body is substituted as text
# before the shell parses the line, so a caller-supplied value can close a quote
# or open a `$(...)` and run as code on the runner. In an *unquoted* heredoc
# (`<< EOF`) the body is expanded too, so a value reaching a step summary that
# way executes as well.
#
# The nine workflows below were migrated to pass such values through `env:` and
# reference them as shell variables. This asserts the migration holds: no
# interpolated caller-controlled value left in a `run:` body — block-scalar,
# folded or single-line — and no unquoted heredoc delimiter. It is a structural
# check on the YAML, so a regression fails here rather than on a runner.
#
# A value that merely *travels* through `env:` is not automatically safe: it can
# leave a step again as a workflow-level output and be interpolated downstream,
# which is why `security-code.yml` also constrains `package-manager` to a known
# set before writing it to `$GITHUB_OUTPUT`.
#
# The four workflows still carrying the old pattern (ci-js, e2e-docker,
# release-npm, deploy-cloudflare-workers) are deliberately out of scope — they
# are migrated separately; see CHANGELOG.md.
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

# The workflows this migration covers.
MIGRATED=(
  ci-terraform.yml
  deploy-terraform.yml
  release-docker.yml
  security-code.yml
  security-config.yml
  security-containers.yml
  security-deps.yml
  security-sbom.yml
  security-secrets.yml
)

# Print every line inside a `run:` body, as "<line-number>:<text>".
# Block scalars (`run: |`, `run: >`) open a block; a single-line `run: cmd` is a
# body of its own and must be scanned too — missing those hides real sinks.
run_block_lines() {
  awk '
    # Block scalar (| or >, with any modifier) or an empty value: opens a block.
    /^[[:space:]]*-?[[:space:]]*run:[[:space:]]*[|>]/ ||
    /^[[:space:]]*-?[[:space:]]*run:[[:space:]]*$/ {
      match($0, /[^ ]/)
      run_indent = RSTART
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
      # A non-blank line at or left of the run: key ends the block.
      if ($0 ~ /[^[:space:]]/) {
        match($0, /[^ ]/)
        if (RSTART <= run_indent && $0 !~ /^[[:space:]]*#/) {
          in_run = 0
          next
        }
      }
      print FNR ":" $0
    }
  ' "$1"
}

for wf in "${MIGRATED[@]}"; do
  path="$WORKFLOWS/$wf"
  [ -f "$path" ] || fail "$wf not found — update this test if it was renamed"

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
  #    called, and `<<-` strips tabs but still expands.
  heredocs="$(grep -nE '<<-?[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$' "$path" || true)"
  if [ -n "$heredocs" ]; then
    echo "$heredocs" >&2
    fail "$wf has an unquoted heredoc delimiter; quote it, e.g. << 'EOF'"
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

echo "PASS: workflow inputs reach run: blocks via env: (${#MIGRATED[@]} workflows)"

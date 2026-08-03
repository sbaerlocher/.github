#!/usr/bin/env bash
# A `${{ inputs.* }}` reference inside a `run:` body is substituted as text
# before the shell parses the line, so a caller-supplied value can close a quote
# or open a `$(...)` and run as code on the runner. In an *unquoted* heredoc
# (`<< EOF`) the body is expanded too, so a value reaching a step summary that
# way executes as well.
#
# The nine workflows below were migrated to pass such values through `env:` and
# reference them as shell variables. This asserts the migration holds: no
# `${{ inputs.* }}` left in their `run:` bodies, and no unquoted heredoc feeding
# the step summary. It is a structural check on the YAML, so a regression fails
# here rather than on a runner.
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

# Print every line inside a `run:` block, as "<line-number>:<text>".
run_block_lines() {
  awk '
    # A run: key opens a block; remember its indentation.
    /^[[:space:]]*-?[[:space:]]*run:[[:space:]]*\|?[[:space:]]*$/ ||
    /^[[:space:]]*-?[[:space:]]*run:[[:space:]]*\|/ {
      match($0, /[^ ]/)
      run_indent = RSTART
      in_run = 1
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

  # 1. No caller input interpolated into a shell body.
  # shellcheck disable=SC2016  # '${{' is the literal string being searched for
  hits="$(run_block_lines "$path" | grep -F '${{' | grep -F 'inputs.' || true)"
  if [ -n "$hits" ]; then
    echo "$hits" >&2
    fail "$wf still interpolates \${{ inputs.* }} inside a run: block"
  fi

  # 2. No unquoted heredoc delimiter: its body would expand a substituted value.
  #    `<< 'EOF'` is fine, `<< EOF` is not.
  heredocs="$(grep -nE '<<[[:space:]]*EOF[[:space:]]*$' "$path" || true)"
  if [ -n "$heredocs" ]; then
    echo "$heredocs" >&2
    fail "$wf has an unquoted heredoc delimiter; quote it as << 'EOF'"
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

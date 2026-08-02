#!/usr/bin/env bash
# Render and inspect the drift-summary block in a GitHub-issue body.
#
# The block is delimited by HTML-comment markers so it can be upserted
# idempotently: re-rendering replaces the block instead of appending a second
# one (the weekly drift cron would otherwise grow the body unbounded).
#
#   drift-issue-body.sh render <base-body> <summary>
#       -> <base-body> with any existing block stripped and a fresh block
#          (containing <summary>) appended. If <summary> is empty, the base
#          body is returned unchanged (no block) — preserves today's behaviour
#          for callers that pass no summary.
#
#   drift-issue-body.sh addresses <body>
#       -> the sorted, unique resource addresses inside the block, one per
#          line (empty if no block). The comparison key for delta detection:
#          sorted so a reordered plan is not mistaken for a change.
set -euo pipefail

START='<!-- drift-summary:start -->'
END='<!-- drift-summary:end -->'

# Strip an existing block (markers included) from stdin.
strip_block() {
  awk -v s="$START" -v e="$END" '
    $0 == s { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip   { print }
  '
}

cmd="${1:-}"
case "$cmd" in
render)
  base="${2:-}"
  summary="${3:-}"
  clean="$(printf '%s' "$base" | strip_block)"
  # Trim trailing blank lines off the base body so the spacing stays stable.
  # awk instead of `sed -e :a -e '/^\n*$/{$d;N;ba}'`: that sed idiom is GNU-only
  # and aborts on BSD sed (macOS) with "unexpected EOF (pending }'s)".
  clean="$(printf '%s\n' "$clean" | awk '
    /^[[:space:]]*$/ { blanks = blanks $0 "\n"; next }
    { printf "%s", blanks; blanks = ""; print }
  ')"
  if [ -z "$summary" ]; then
    printf '%s\n' "$clean"
    exit 0
  fi
  # shellcheck disable=SC2016  # backticks are a literal markdown fence, not command substitution
  printf '%s\n\n%s\n\n### Drifting resources\n\n```\n%s\n```\n\n%s\n' \
    "$clean" "$START" "$summary" "$END"
  ;;
addresses)
  body="${2:-}"
  # Lines inside the block: "<action> <address>". Sorted and unique — the action
  # column is deliberately ignored so a switch from update->replace on the same
  # resource does not count as a delta while the address set stays the same.
  # (Delta = address set.)
  # Only lines inside the code fence within the block count — heading and blank
  # lines stay out. Address = everything after the first space (the action
  # column is space-free thanks to join("+"), while the address may contain
  # spaces in for_each keys, e.g. authentik_group.admins["my key"]).
  printf '%s' "$body" |
    awk -v s="$START" -v e="$END" '
        $0 == s { inb = 1; next }
        $0 == e { inb = 0; fence = 0; next }
        inb && $0 == "```" { fence = !fence; next }
        inb && fence && $0 ~ / / { sub(/^[^ ]+ /, ""); print }
      ' |
    sort -u
  ;;
*)
  echo "usage: drift-issue-body.sh {render <base> <summary>|addresses <body>}" >&2
  exit 2
  ;;
esac

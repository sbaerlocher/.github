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
  # Trailing leerzeilen des Basis-Bodys kappen, damit der Abstand stabil ist.
  clean="$(printf '%s\n' "$clean" | sed -e :a -e '/^\n*$/{$d;N;ba}')"
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
  # Zeilen im Block: "<action> <address>". Adresse = zweites Feld. Sortiert,
  # eindeutig — die Aktions-Spalte bewusst ignoriert, damit ein Wechsel
  # update->replace derselben Resource nicht als Delta zählt, wenn die
  # Adressmenge gleich bleibt. (Delta = Adressmenge, siehe Konzept.)
  # Nur Zeilen im Code-Fence innerhalb des Blocks zählen — Heading und
  # Leerzeilen bleiben draussen. Adresse = zweites Feld.
  printf '%s' "$body" |
    awk -v s="$START" -v e="$END" '
        $0 == s { inb = 1; next }
        $0 == e { inb = 0; fence = 0; next }
        inb && $0 == "```" { fence = !fence; next }
        inb && fence && $2 != "" { print $2 }
      ' |
    sort -u
  ;;
*)
  echo "usage: drift-issue-body.sh {render <base> <summary>|addresses <body>}" >&2
  exit 2
  ;;
esac

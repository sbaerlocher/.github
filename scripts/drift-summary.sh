#!/usr/bin/env bash
# Extract a value-free drift summary from `terraform show -json <plan>`.
#
# Reads the plan JSON on stdin, writes one line per drifting resource to
# stdout: "<action> <address>" (e.g. "update authentik_group.admins").
#
# LEVEL-A BOUNDARY (value freedom): the jq query reads `.address` and
# `.change.actions` exclusively. It NEVER touches `.change.before`/`.after`,
# so no attribute value (which may contain secrets, see
# TF_VAR_authentik_token) can ever reach a GitHub issue. Extending the query
# breaks assertion 3 in test-drift-summary.sh first.
#
# no-op resources (not real drift) are filtered out. The output is capped at
# CAP lines (job output limit 1 MB). An error in `jq` or a broken input ->
# empty output, exit 0: a broken summary must never suppress the drift report
# itself.
set -uo pipefail

CAP=50

INPUT="$(cat)"

# Real changes only: filter out no-op (no drift) and read (deferred data-source
# reads, not config drift, just noise). Replace is ["delete","create"] and
# stays in. Only .address + .change.actions are read.
LINES="$(printf '%s' "$INPUT" | jq -r '
  .resource_changes // []
  | map(select((.change.actions // []) != ["no-op"] and (.change.actions // []) != ["read"]))
  | .[]
  | "\(.change.actions | join("+")) \(.address)"
' 2>/dev/null)" || LINES=""

# Empty plan / broken input -> empty output, exit 0.
[ -z "$LINES" ] && exit 0

TOTAL="$(printf '%s\n' "$LINES" | wc -l)"
if [ "$TOTAL" -gt "$CAP" ]; then
  printf '%s\n' "$LINES" | head -n "$CAP"
  printf '… %d more (truncated)\n' "$((TOTAL - CAP))"
else
  printf '%s\n' "$LINES"
fi

exit 0

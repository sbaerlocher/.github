#!/usr/bin/env bash
# Extract a value-free drift summary from `terraform show -json <plan>`.
#
# Reads the plan JSON on stdin, writes one line per drifting resource to
# stdout: "<action> <address>" (e.g. "update authentik_group.admins").
#
# LEVEL-A GRENZE (Wert-Freiheit): die jq-Query liest ausschliesslich
# `.address` und `.change.actions`. Sie fasst `.change.before`/`.after`
# NIE an, damit kein Attributwert (der Secrets enthalten kann, siehe
# TF_VAR_authentik_token) je in ein GitHub-Issue gelangt. Wer die Query
# erweitert, bricht zuerst Assertion 3 in test-drift-summary.sh.
#
# no-op-Resourcen (kein echter Drift) werden herausgefiltert. Der Output ist
# bei CAP Zeilen gedeckelt (Job-Output-Limit 1 MB). Fehler in `jq` oder
# kaputter Input -> leerer Output, Exit 0: ein kaputter Summary darf die
# Drift-Meldung selbst nie unterdrücken.
set -uo pipefail

CAP=50

INPUT="$(cat)"

# Alle Aktionen ausser reinem ["no-op"]. Replace ist ["delete","create"] und
# bleibt drin. Nur .address + .change.actions werden gelesen.
LINES="$(printf '%s' "$INPUT" | jq -r '
  .resource_changes // []
  | map(select((.change.actions // []) != ["no-op"]))
  | .[]
  | "\(.change.actions | join("+")) \(.address)"
' 2>/dev/null)" || LINES=""

# Leerer Plan / kaputter Input -> leerer Output, Exit 0.
[ -z "$LINES" ] && exit 0

TOTAL="$(printf '%s\n' "$LINES" | wc -l)"
if [ "$TOTAL" -gt "$CAP" ]; then
  printf '%s\n' "$LINES" | head -n "$CAP"
  printf '… %d more (truncated)\n' "$((TOTAL - CAP))"
else
  printf '%s\n' "$LINES"
fi

exit 0

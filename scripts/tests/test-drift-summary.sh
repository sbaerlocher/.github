#!/usr/bin/env bash
# Self-check for scripts/drift-summary.sh — plain bash asserts, no framework.
# Run: scripts/tests/test-drift-summary.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../drift-summary.sh"
FIXTURE="$HERE/fixtures/plan-drift.json"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# 1 — driftende Adressen erscheinen mit Aktion, no-op wird gefiltert.
OUT="$(cat "$FIXTURE" | "$SCRIPT")"
echo "$OUT" | grep -q 'authentik_group.admins' || fail "update address missing"
echo "$OUT" | grep -q 'authentik_application.grafana' || fail "create address missing"
echo "$OUT" | grep -q 'authentik_provider_oauth2.grafana' || fail "delete address missing"
echo "$OUT" | grep -q 'authentik_group.replaced' || fail "replace address missing"

# 2 — no-op darf nicht im Summary stehen (kein echter Drift).
if echo "$OUT" | grep -q 'authentik_flow.unchanged'; then
  fail "no-op resource must be filtered out"
fi

# 2b — data-source read (aufgeschoben) ist kein Drift, muss gefiltert sein.
if echo "$OUT" | grep -q 'data.authentik_user.lookup'; then
  fail "read data source must be filtered out"
fi

# 2c — Adresse mit Space (for_each-String-Key) bleibt vollständig erhalten.
echo "$OUT" | grep -qF 'authentik_group.spaced["my key"]' || fail "spaced address truncated/missing"

# 3 — WERT-FREIHEIT (Anker der Level-A-Grenze): kein Attributwert aus
# before/after darf im Output landen. Failt zuerst, wenn die Query je
# .change.before/.after anfasst.
if echo "$OUT" | grep -q 'LEAKME'; then
  fail "attribute value from before/after leaked into output"
fi

# 4 — Deckelung: viele Resourcen -> Output <= 50 Zeilen + Hinweiszeile.
BIG="$(jq -n '{resource_changes: [range(80) | {address: ("authentik_group.g\(.)"), change: {actions: ["update"]}}]}' |
  "$SCRIPT")"
LINES="$(echo "$BIG" | wc -l)"
[ "$LINES" -le 51 ] || fail "output not capped (got $LINES lines)"
echo "$BIG" | grep -qi 'truncat\|more\|weitere' || fail "cap notice missing when truncated"

# 5 — kaputter Input -> Exit 0, leerer/harmloser Output (Summary darf die
# Drift-Meldung nie unterdrücken).
set +e
echo 'not json {{{' | "$SCRIPT" >/dev/null 2>&1
RC=$?
set -e
[ "$RC" -eq 0 ] || fail "broken input must exit 0 (got $RC)"

# 6 — leerer Plan (keine changes) -> leerer Output, Exit 0.
EMPTY="$(echo '{"resource_changes": []}' | "$SCRIPT")"
[ -z "$EMPTY" ] || fail "empty plan must yield empty output"

echo "PASS: drift-summary.sh"

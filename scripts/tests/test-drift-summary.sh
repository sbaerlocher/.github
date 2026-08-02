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

# 1 — drifting addresses appear with their action, no-op is filtered out.
OUT="$(cat "$FIXTURE" | "$SCRIPT")"
echo "$OUT" | grep -q 'authentik_group.admins' || fail "update address missing"
echo "$OUT" | grep -q 'authentik_application.grafana' || fail "create address missing"
echo "$OUT" | grep -q 'authentik_provider_oauth2.grafana' || fail "delete address missing"
echo "$OUT" | grep -q 'authentik_group.replaced' || fail "replace address missing"

# 2 — no-op must not appear in the summary (not real drift).
if echo "$OUT" | grep -q 'authentik_flow.unchanged'; then
  fail "no-op resource must be filtered out"
fi

# 2b — a deferred data-source read is not drift and must be filtered out.
if echo "$OUT" | grep -q 'data.authentik_user.lookup'; then
  fail "read data source must be filtered out"
fi

# 2c — an address containing a space (for_each string key) stays intact.
echo "$OUT" | grep -qF 'authentik_group.spaced["my key"]' || fail "spaced address truncated/missing"

# 3 — VALUE FREEDOM (anchor of the Level-A boundary): no attribute value from
# before/after may reach the output. This fails first if the query ever touches
# .change.before/.after.
if echo "$OUT" | grep -q 'LEAKME'; then
  fail "attribute value from before/after leaked into output"
fi

# 4 — capping: many resources -> output <= 50 lines plus a notice line.
BIG="$(jq -n '{resource_changes: [range(80) | {address: ("authentik_group.g\(.)"), change: {actions: ["update"]}}]}' |
  "$SCRIPT")"
LINES="$(echo "$BIG" | wc -l)"
[ "$LINES" -le 51 ] || fail "output not capped (got $LINES lines)"
echo "$BIG" | grep -qi 'truncat\|more' || fail "cap notice missing when truncated"

# 5 — broken input -> exit 0 and empty/harmless output (the summary must never
# suppress the drift report).
set +e
echo 'not json {{{' | "$SCRIPT" >/dev/null 2>&1
RC=$?
set -e
[ "$RC" -eq 0 ] || fail "broken input must exit 0 (got $RC)"

# 6 — empty plan (no changes) -> empty output, exit 0.
EMPTY="$(echo '{"resource_changes": []}' | "$SCRIPT")"
[ -z "$EMPTY" ] || fail "empty plan must yield empty output"

echo "PASS: drift-summary.sh"

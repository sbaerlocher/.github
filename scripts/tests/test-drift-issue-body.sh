#!/usr/bin/env bash
# Self-check for scripts/drift-issue-body.sh — plain bash asserts, no framework.
# Run: scripts/tests/test-drift-issue-body.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../drift-issue-body.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

SUMMARY="update authentik_group.admins
create authentik_application.grafana"

BASE="## Terraform Drift Detected

Some intro text.

**Triggered:** 2026-07-20 07:14 UTC"

# render <base-body> <summary> -> body with marker block appended.
BODY1="$("$SCRIPT" render "$BASE" "$SUMMARY")"
echo "$BODY1" | grep -q '<!-- drift-summary:start -->' || fail "start marker missing"
echo "$BODY1" | grep -q '<!-- drift-summary:end -->' || fail "end marker missing"
echo "$BODY1" | grep -q 'authentik_group.admins' || fail "summary content missing"

# 1 — IDEMPOTENZ: re-render über einen Body, der den Block schon hat, ersetzt
# ihn, dupliziert ihn nicht (sonst wächst der Body bei wöchentlichem Cron).
BODY2="$("$SCRIPT" render "$BODY1" "$SUMMARY")"
COUNT="$(echo "$BODY2" | grep -c '<!-- drift-summary:start -->')"
[ "$COUNT" -eq 1 ] || fail "marker block duplicated on re-render (got $COUNT)"

# 2 — addresses <body> -> sortierte, eindeutige Adressliste aus dem Block.
ADDRS="$("$SCRIPT" addresses "$BODY1")"
EXPECTED="authentik_application.grafana
authentik_group.admins"
[ "$ADDRS" = "$EXPECTED" ] || fail "addresses not sorted/extracted correctly:
got:
$ADDRS
want:
$EXPECTED"

# 3 — REIHENFOLGE-UNABHÄNGIGKEIT: gleiche Adressen in anderer Summary-Reihenfolge
# -> identische addresses-Ausgabe (sonst falsches Delta bei jedem Cron).
SUMMARY_REORDERED="create authentik_application.grafana
update authentik_group.admins"
BODY_R="$("$SCRIPT" render "$BASE" "$SUMMARY_REORDERED")"
ADDRS_R="$("$SCRIPT" addresses "$BODY_R")"
[ "$ADDRS" = "$ADDRS_R" ] || fail "address extraction depends on order"

# 4 — leerer Block (kein Drift-Summary) -> addresses leer.
EMPTY_ADDRS="$("$SCRIPT" addresses "$BASE")"
[ -z "$EMPTY_ADDRS" ] || fail "addresses on body without block must be empty"

# 5 — Adresse mit Space (for_each-String-Key) wird vollständig extrahiert, nicht
# am ersten Space abgeschnitten (sonst kollabieren zwei Adressen unter sort -u
# und ein Delta wird verschluckt).
SPACED='update authentik_group.admins["my key"]
update authentik_group.admins["other key"]'
BODY_S="$("$SCRIPT" render "$BASE" "$SPACED")"
ADDRS_S="$("$SCRIPT" addresses "$BODY_S")"
EXP_S='authentik_group.admins["my key"]
authentik_group.admins["other key"]'
[ "$ADDRS_S" = "$EXP_S" ] || fail "spaced addresses truncated:
got:
$ADDRS_S
want:
$EXP_S"

echo "PASS: drift-issue-body.sh"

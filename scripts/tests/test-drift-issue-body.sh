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

# 1 — IDEMPOTENCE: re-rendering over a body that already has the block replaces
# it instead of duplicating it (otherwise the weekly cron grows the body).
BODY2="$("$SCRIPT" render "$BODY1" "$SUMMARY")"
COUNT="$(echo "$BODY2" | grep -c '<!-- drift-summary:start -->')"
[ "$COUNT" -eq 1 ] || fail "marker block duplicated on re-render (got $COUNT)"

# 2 — addresses <body> -> sorted, unique address list from the block.
ADDRS="$("$SCRIPT" addresses "$BODY1")"
EXPECTED="authentik_application.grafana
authentik_group.admins"
[ "$ADDRS" = "$EXPECTED" ] || fail "addresses not sorted/extracted correctly:
got:
$ADDRS
want:
$EXPECTED"

# 3 — ORDER INDEPENDENCE: the same addresses in a different summary order yield
# identical addresses output (otherwise every cron run reports a bogus delta).
SUMMARY_REORDERED="create authentik_application.grafana
update authentik_group.admins"
BODY_R="$("$SCRIPT" render "$BASE" "$SUMMARY_REORDERED")"
ADDRS_R="$("$SCRIPT" addresses "$BODY_R")"
[ "$ADDRS" = "$ADDRS_R" ] || fail "address extraction depends on order"

# 4 — no block (no drift summary) -> addresses is empty.
EMPTY_ADDRS="$("$SCRIPT" addresses "$BASE")"
[ -z "$EMPTY_ADDRS" ] || fail "addresses on body without block must be empty"

# 5 — an address containing a space (for_each string key) is extracted in full
# rather than cut at the first space (otherwise two addresses collapse under
# sort -u and a delta is swallowed).
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

# 6 — trailing whitespace-only lines in the base body are trimmed so the spacing
# before the marker block stays stable. Command substitution alone strips only
# genuinely empty trailing lines, not a line made of spaces.
BASE_TRAILING="$BASE

   "
BODY_T="$("$SCRIPT" render "$BASE_TRAILING" "$SUMMARY")"
[ "$BODY_T" = "$BODY1" ] || fail "trailing whitespace-only lines not trimmed:
got:
$(printf '%s' "$BODY_T" | od -c | tail -5)
want:
$(printf '%s' "$BODY1" | od -c | tail -5)"

echo "PASS: drift-issue-body.sh"

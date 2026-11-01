#!/usr/bin/env bash
# The custom regex manager for Helm charts in fleet.yaml used to match only the
# key order `repo` → `chart` → `version`. A fleet.yaml that wrote the same three
# keys in any other order was skipped without a word, and its chart never got
# an update — three bundles in sbaerlocher/applications sat on a stale
# app-template that way. The manager now carries one matchString per order.
#
# Each key is anchored on a newline plus exactly two spaces, so a `version:`
# nested under `values:` or under `targetCustomizations` cannot stand in for the
# chart's own version, and the gap between keys stops at the first line that
# starts in column 0, so a match cannot reach into the next top-level block.
#
# The assertions run the regexes from renovate-kubernetes.json itself rather
# than a copy, with the `g` flag Renovate compiles them with. A copy here would
# keep passing after the preset regressed.
#
# Run: scripts/tests/test-renovate-fleet-regex.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PRESET="$REPO/renovate-kubernetes.json"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -f "$PRESET" ] || fail "renovate-kubernetes.json not found at $PRESET"

# Selected by description prefix, so the OCI manager next to it stays out.
PREFIX='Fleet Helm Charts in fleet.yaml (standard HTTP repos'
MANAGERS="$(jq --arg p "$PREFIX" '[.customManagers[] | select(.description | startswith($p))]' "$PRESET")"
[ "$(jq length <<<"$MANAGERS")" -eq 1 ] || fail "expected exactly one manager whose description starts with '$PREFIX'"
MATCH_STRINGS="$(jq -c '.[0].matchStrings' <<<"$MANAGERS")"

# matches <yaml…> → one `registryUrl|depName|currentValue` line per match,
# summed over all matchStrings, like Renovate's default `any` strategy.
matches() {
  # shellcheck disable=SC2016 # ${g.…} is a JavaScript template, not shell
  printf '%s\n' "$@" | MATCH_STRINGS="$MATCH_STRINGS" node -e '
    const content = require("fs").readFileSync(0, "utf8");
    for (const s of JSON.parse(process.env.MATCH_STRINGS)) {
      for (const m of content.matchAll(new RegExp(s, "g"))) {
        const g = m.groups;
        console.log(`${g.registryUrl}|${g.depName}|${g.currentValue}`);
      }
    }'
}

# assert_matches <label> <expected-lines> <yaml…>
assert_matches() {
  local label="$1" expected="$2" actual
  shift 2
  actual="$(matches "$@")"
  [ "$actual" = "$expected" ] || fail "$label: expected [$expected], got [$actual]"
}

R='  repo: https://bjw-s-labs.github.io/helm-charts'
C='  chart: app-template'
V='  version: "4.6.2"'
WANT='https://bjw-s-labs.github.io/helm-charts|app-template|4.6.2'

# --- 1. every key order yields exactly one match ------------------------------

assert_matches "repo chart version" "$WANT" 'helm:' "$R" "$C" "$V"
assert_matches "repo version chart" "$WANT" 'helm:' "$R" "$V" "$C"
assert_matches "chart repo version" "$WANT" 'helm:' "$C" "$R" "$V"
assert_matches "chart version repo" "$WANT" 'helm:' "$C" "$V" "$R"
assert_matches "version repo chart" "$WANT" 'helm:' "$V" "$R" "$C"
assert_matches "version chart repo" "$WANT" 'helm:' "$V" "$C" "$R"

# --- 2. quoting, http and lines between the keys ------------------------------

assert_matches "single quotes and http" 'http://charts.example.com|nginx|1.0.0' \
  'helm:' "  chart: 'nginx'" "  repo: 'http://charts.example.com'" "  version: '1.0.0'"
assert_matches "comment and blank line between keys" "$WANT" \
  'helm:' "$C" '  # pinned until the next upgrade window' '' "$R" "$V"

# --- 3. what must not match ---------------------------------------------------

# OCI charts belong to the sibling manager.
assert_matches "OCI chart without repo" '' \
  'helm:' '  chart: oci://ghcr.io/example/chart' '  version: 1.0.0'

# A `version:` in a later top-level block is not this chart's version.
assert_matches "version only under targetCustomizations" '' \
  'helm:' "$R" "$C" 'targetCustomizations:' '  - name: prod' '    helm:' '      version: 1.0.0'

# A nested `values.version` is chart configuration, not the chart version.
assert_matches "nested values.version ignored" \
  'https://bjw-s-labs.github.io/helm-charts|app-template|1.2.3' \
  'helm:' '  values:' '    version: 9.9.9' "$R" "$C" '  version: 1.2.3'

echo "PASS: renovate fleet regex"

#!/usr/bin/env bash
# The generic `# renovate: datasource=… depName=…` marker manager in
# renovate-base.json scans every *.json file, including a consumer's own
# renovate.json. velometrics keeps a custom manager whose matchString contains
# the marker as regex text (`datasource=(?<datasource>\S+) depName=…`); the base
# manager read that line as a marker and reported `Unknown datasource
# "(?<datasource>\S+)"` as a package lookup failure. The datasource now has to
# start with a letter and the depName must not start with `(`, which keeps regex
# text out while real markers, `custom.<name>` datasources included, still
# match.
#
# The assertions run the regex from renovate-base.json itself rather than a
# copy, so a later edit to the matchString is tested as written.
#
# Run: scripts/tests/test-renovate-marker-regex.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PRESET="$REPO/renovate-base.json"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -f "$PRESET" ] || fail "renovate-base.json not found at $PRESET"

PREFIX='Update versions in comments'
MATCH_STRINGS="$(jq -c --arg p "$PREFIX" '[.customManagers[] | select(.description | startswith($p))][0].matchStrings' "$PRESET")"
[ "$MATCH_STRINGS" != "null" ] || fail "no manager whose description starts with '$PREFIX'"

# matches <text…> → one `datasource|depName|currentValue` line per match.
matches() {
  # shellcheck disable=SC2016 # ${g.…} is a JavaScript template, not shell
  printf '%s\n' "$@" | MATCH_STRINGS="$MATCH_STRINGS" node -e '
    const content = require("fs").readFileSync(0, "utf8");
    for (const s of JSON.parse(process.env.MATCH_STRINGS)) {
      for (const m of content.matchAll(new RegExp(s, "g"))) {
        const g = m.groups;
        console.log(`${g.datasource}|${g.depName}|${g.currentValue}`);
      }
    }'
}

# assert_matches <label> <expected-lines> <text…>
assert_matches() {
  local label="$1" expected="$2" actual
  shift 2
  actual="$(matches "$@")"
  [ "$actual" = "$expected" ] || fail "$label: expected [$expected], got [$actual]"
}

# --- real markers still match -------------------------------------------------

assert_matches "yaml marker" 'github-releases|kubernetes/kubectl|1.34.1' \
  '# renovate: datasource=github-releases depName=kubernetes/kubectl' 'KUBECTL_VERSION: "1.34.1"'
assert_matches "custom datasource with uppercase and underscore" 'custom.my_Tool|foo/bar|2.0.0' \
  '# renovate: datasource=custom.my_Tool depName=foo/bar' 'version: 2.0.0'
assert_matches "datasource typo still surfaces as a lookup" 'Docker|alpine|3.24' \
  '# renovate: datasource=Docker depName=alpine' 'image: "3.24"'

# --- regex text in a renovate config does not match ---------------------------

assert_matches "captured datasource (velometrics)" '' \
  '"# renovate: datasource=(?<datasource>\\S+) depName=(?<depName>\\S+)\\s+\\w+_VERSION=(?<currentValue>\\S+)",' \
  '  "x": "y"'
assert_matches "fixed datasource, captured depName" '' \
  '"# renovate: datasource=docker depName=(?<depName>\\S+)\\n[^:]*:\\s*(?<currentValue>\\S+)",' \
  '  "x": "y"'

echo "PASS: renovate marker regex"

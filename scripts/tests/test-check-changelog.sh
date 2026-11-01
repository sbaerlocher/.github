#!/usr/bin/env bash
# Self-check for scripts/check-changelog.sh — plain bash asserts, no framework.
# Run: scripts/tests/test-check-changelog.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../check-changelog.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# expect <exit-code> <title> [path...] — feeds the paths on stdin, one per line.
expect() {
  local want="$1" title="$2" rc
  shift 2
  set +e
  if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@" | "$SCRIPT" "$title" >/dev/null 2>&1
  else
    "$SCRIPT" "$title" </dev/null >/dev/null 2>&1
  fi
  rc=$?
  set -e
  [ "$rc" -eq "$want" ] || fail "'$title' with [$*] must exit $want (got $rc)"
}

WF=.github/workflows/ci-go.yml

# 1 — exempt types, untriggered paths and empty input pass.
expect 0 'chore(deps): update actions/checkout' "$WF"
expect 0 'ci: run lint on push' .github/workflows/pull-request.yml
expect 0 'fix(ci-go): pin go version' "$WF" CHANGELOG.md
expect 0 'feat: describe usage' README.md
expect 0 'fix: repo-level renovate rule' renovate.json
expect 0 'feat: add x'

# 2 — a triggering path under a required type needs the root CHANGELOG.md.
expect 1 'fix(ci-go): pin go version' "$WF"
expect 1 'feat: add dde option' .github/actions/setup-dde/action.yml
expect 1 'refactor: split preset' renovate-base.json

# 3 — `!` makes any type required; only the root CHANGELOG.md counts.
expect 1 'ci(x)!: drop input' "$WF"
expect 1 'fix!: drop input' "$WF" docs/CHANGELOG.md

# 4 — a title outside the schema is red, so a typo is not a bypass.
expect 1 'feature: add x' "$WF"
expect 1 'Revert "feat: x"' "$WF"

# 5 — missing title argument is a usage error.
set +e
"$SCRIPT" </dev/null >/dev/null 2>&1
RC=$?
set -e
[ "$RC" -eq 2 ] || fail "missing argument must exit 2 (got $RC)"

# 6 — the failure message names the type and the triggering path.
set +e
ERR="$(printf '%s\n' "$WF" | "$SCRIPT" 'fix(ci-go): pin go version' 2>&1 >/dev/null)"
set -e
grep -qF 'fix' <<<"$ERR" || fail "stderr must name the type"
grep -qF "$WF" <<<"$ERR" || fail "stderr must name the triggering path"

echo "PASS: check-changelog.sh"

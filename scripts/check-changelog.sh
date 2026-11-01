#!/usr/bin/env bash
# Require a CHANGELOG.md entry for consumer-visible PRs.
#
# Usage: git diff --name-only <base>...<head> | check-changelog.sh <pr-title>
#
# A PR needs a change to the root CHANGELOG.md when both hold:
#   - its title type is feat, fix, perf or refactor, or carries `!`
#     (squash-only, so the title becomes the commit subject on main);
#   - it touches .github/workflows/**, .github/actions/** or a root
#     renovate-*.json preset. renovate.json is this repo's own config and does
#     not count.
# chore, ci, docs, test, build, style and revert are exempt, which also covers
# Renovate's `chore(deps)` PRs without a special case.
#
# A title outside the Conventional Commits schema (unknown type, GitHub's
# `Revert "…"`) fails: otherwise a typo in the type would be a bypass.
#
# Exit 0 = ok, 1 = entry missing or title invalid, 2 = no title argument.
set -uo pipefail

[ "$#" -ge 1 ] || {
  echo 'usage: check-changelog.sh <pr-title> < changed-paths' >&2
  exit 2
}
TITLE="$1"

RE='^([a-z]+)(\([^()]*\))?(!)?: .+'
if ! [[ "$TITLE" =~ $RE ]]; then
  echo "PR title is not a Conventional Commits subject: $TITLE" >&2
  exit 1
fi
TYPE="${BASH_REMATCH[1]}"
BANG="${BASH_REMATCH[3]}"

case "$TYPE" in
feat | fix | perf | refactor) REQUIRED=1 ;;
chore | ci | docs | test | build | style | revert) REQUIRED=0 ;;
*)
  echo "Unknown Conventional Commits type '$TYPE' in PR title: $TITLE" >&2
  exit 1
  ;;
esac
[ -n "$BANG" ] && REQUIRED=1
[ "$REQUIRED" -eq 1 ] || exit 0

TRIGGERS=()
HAS_CHANGELOG=0
while IFS= read -r path; do
  case "$path" in
  CHANGELOG.md) HAS_CHANGELOG=1 ;;
  .github/workflows/* | .github/actions/*) TRIGGERS+=("$path") ;;
  renovate-*.json) [[ "$path" == */* ]] || TRIGGERS+=("$path") ;;
  esac
done

[ "${#TRIGGERS[@]}" -eq 0 ] && exit 0
[ "$HAS_CHANGELOG" -eq 1 ] && exit 0

echo "PR type '$TYPE$BANG' changes consumer-facing files but not CHANGELOG.md:" >&2
printf '  %s\n' "${TRIGGERS[@]}" >&2
echo 'Add an entry under the merge date, or use an exempt type (chore, ci, docs, test, build, style, revert).' >&2
exit 1

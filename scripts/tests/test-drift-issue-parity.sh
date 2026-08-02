#!/usr/bin/env bash
# Parity check: the inline render/addresses copy in ops-drift-issue.yml must
# behave exactly like scripts/drift-issue-body.sh.
#
# The workflow keeps its own copy on purpose (a reusable workflow cannot check
# out its own ref — see the comment above the `Upsert drift issue` step), and
# the contract there said "kept equal by hand". That hand-sync drifted twice
# and both times was caught by eye. This closes it.
#
# Behaviour-based, not textual: the workflow's `run:` block is extracted from
# the YAML (not by a hardcoded line range, which goes stale on the next edit),
# its function definitions are sourced, and the same inputs go through both
# implementations. Comparing outputs catches semantic drift while ignoring
# indentation and comment churn.
#
# Run: scripts/tests/test-drift-issue-parity.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SCRIPT="$REPO/scripts/drift-issue-body.sh"
WORKFLOW="$REPO/.github/workflows/ops-drift-issue.yml"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || fail "python3 required to parse the workflow YAML"

# Pull the `run:` body of the Upsert step out of the workflow. PyYAML resolves
# the block scalar, so the result is already de-indented shell.
RUN_BLOCK="$(
  python3 - "$WORKFLOW" <<'PY'
import sys, yaml

with open(sys.argv[1]) as fh:
    doc = yaml.safe_load(fh)

for job in doc.get("jobs", {}).values():
    for step in job.get("steps", []):
        if step.get("name") == "Upsert drift issue":
            sys.stdout.write(step["run"])
            sys.exit(0)

sys.exit("step 'Upsert drift issue' not found in workflow")
PY
)" || fail "could not extract the workflow run block"

# Keep only the leading definition part: everything up to the first line that
# is neither a function definition nor inside one. The step continues with `gh`
# calls that need a token and a live repo; sourcing those would be a network
# call, not a unit test.
DEFS="$(
  printf '%s\n' "$RUN_BLOCK" | awk '
    /^TITLE=/ { exit }
    { print }
  '
)"

printf '%s\n' "$DEFS" | grep -q '^strip_block()' || fail "strip_block missing from extracted workflow block"
printf '%s\n' "$DEFS" | grep -q '^render()' || fail "render missing from extracted workflow block"
printf '%s\n' "$DEFS" | grep -q '^addresses()' || fail "addresses missing from extracted workflow block"

# Source the workflow copy into this shell. `set -euo pipefail` inside the
# block is harmless — the test already runs under it.
# shellcheck disable=SC1091  # sourcing generated content by design
source /dev/stdin <<<"$DEFS"

BASE="## Terraform Drift Detected

Some intro text.

**Triggered:** 2026-07-20 07:14 UTC"

SUMMARY="update authentik_group.admins
create authentik_application.grafana"

# Cases mirror the behaviour classes test-drift-issue-body.sh pins on the
# script: plain render, idempotent re-render, empty summary, trailing
# whitespace, spaced for_each keys, and address extraction with/without block.
run_case() { # run_case <name> <base> <summary>
  local name="$1" base="$2" summary="$3"
  local script_body workflow_body script_addrs workflow_addrs

  script_body="$("$SCRIPT" render "$base" "$summary")"
  workflow_body="$(render "$base" "$summary")"
  [ "$script_body" = "$workflow_body" ] || fail "render drifted for case '$name':
script:
$script_body
workflow:
$workflow_body"

  script_addrs="$("$SCRIPT" addresses "$script_body")"
  workflow_addrs="$(addresses "$workflow_body")"
  [ "$script_addrs" = "$workflow_addrs" ] || fail "addresses drifted for case '$name':
script:
$script_addrs
workflow:
$workflow_addrs"
}

# 1 — plain render over a clean base body.
run_case "plain" "$BASE" "$SUMMARY"

# 2 — re-render over a body that already carries the block (idempotency path
# through strip_block).
BODY_WITH_BLOCK="$("$SCRIPT" render "$BASE" "$SUMMARY")"
run_case "re-render" "$BODY_WITH_BLOCK" "$SUMMARY"

# 3 — empty summary takes the early-return branch, no block appended.
run_case "empty summary" "$BASE" ""

# 4 — trailing whitespace-only lines exercise the awk trailing-blank trim, the
# exact spot where the GNU-sed idiom lived when the two copies last diverged.
run_case "trailing whitespace" "$BASE

   " "$SUMMARY"

# 5 — for_each keys with spaces must survive the address split in both copies.
run_case "spaced addresses" "$BASE" 'update authentik_group.admins["my key"]
update authentik_group.admins["other key"]'

# 6 — addresses over a body without a block is empty in both copies.
SCRIPT_EMPTY="$("$SCRIPT" addresses "$BASE")"
WORKFLOW_EMPTY="$(addresses "$BASE")"
[ "$SCRIPT_EMPTY" = "$WORKFLOW_EMPTY" ] || fail "addresses on block-less body drifted:
script: '$SCRIPT_EMPTY'
workflow: '$WORKFLOW_EMPTY'"
[ -z "$WORKFLOW_EMPTY" ] || fail "addresses on block-less body must be empty"

echo "PASS: ops-drift-issue.yml <-> drift-issue-body.sh parity"

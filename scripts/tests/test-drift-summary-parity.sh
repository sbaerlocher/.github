#!/usr/bin/env bash
# Parity check: the inline jq query in the `Drift Summary Extraction` step of
# deploy-terraform.yml must behave exactly like scripts/drift-summary.sh.
#
# The workflow keeps its own copy on purpose (it checks out the consumer repo,
# so the script is not on disk at runtime — see the comment above the step),
# and the contract there said "kept equal by hand". Nothing enforced it. This
# closes it, same pattern as test-drift-issue-parity.sh.
#
# Behaviour-based, not textual: the `run:` block is extracted from the YAML
# (not by a hardcoded line range, which goes stale on the next edit), the jq
# expression is cut out of it, and the same fixture goes through both copies.
# Comparing outputs catches semantic drift while ignoring indentation churn.
#
# Unlike ops-drift-issue.yml, this step has no shell functions to source. The
# query is compared on its own first (assertions 1-2, which is where the
# value-freedom guarantee lives), then the whole step runs against a stubbed
# `terraform` and a temporary $GITHUB_OUTPUT (assertions 3-5), so the cap
# threshold and the truncation notice are covered rather than re-derived.
#
# Run: scripts/tests/test-drift-summary-parity.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SCRIPT="$REPO/scripts/drift-summary.sh"
WORKFLOW="$REPO/.github/workflows/deploy-terraform.yml"
FIXTURE="$HERE/fixtures/plan-drift.json"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || fail "python3 required to parse the workflow YAML"

# Pull the `run:` body of the Drift Summary step out of the workflow. PyYAML
# resolves the block scalar, so the result is already de-indented shell.
RUN_BLOCK="$(
  python3 - "$WORKFLOW" <<'PY'
import sys, yaml

with open(sys.argv[1]) as fh:
    doc = yaml.safe_load(fh)

for job in doc.get("jobs", {}).values():
    for step in job.get("steps", []):
        if step.get("name") == "Drift Summary Extraction":
            sys.stdout.write(step["run"])
            sys.exit(0)

sys.exit("step 'Drift Summary Extraction' not found in workflow")
PY
)" || fail "could not extract the workflow run block"

# Cut the jq expression out of the block: everything between `jq -r '` and the
# next line whose first non-blank character is the closing quote.
QUERY="$(
  printf '%s\n' "$RUN_BLOCK" | awk "
    /jq -r '/ { grab = 1; next }
    grab && /^[[:space:]]*'/ { exit }
    grab { print }
  "
)"

# A silently empty extraction would compare "" against "" further down and pass.
printf '%s\n' "$QUERY" | grep -q 'resource_changes' || fail "jq query extraction came up empty (workflow step reshaped?)"

# 1 — same fixture through both copies must yield the same lines. The fixture
# covers update/create/delete/replace plus the filtered no-op and read cases.
PLAN="$(cat "$FIXTURE")"
WORKFLOW_OUT="$(printf '%s' "$PLAN" | jq -r "$QUERY")" || fail "workflow query failed on the fixture"
SCRIPT_OUT="$(printf '%s' "$PLAN" | "$SCRIPT")"
[ "$WORKFLOW_OUT" = "$SCRIPT_OUT" ] || fail "query drifted on plan-drift.json:
workflow:
$WORKFLOW_OUT
script:
$SCRIPT_OUT"

# 2 — WERT-FREIHEIT: the level-A comment above the step claims the inline query
# never touches .change.before/.after. The fixture carries LEAKME markers in
# both, so a query that widened its field selection shows up right here. Drift
# on this one would be a secret leak into a GitHub issue body.
if printf '%s\n' "$WORKFLOW_OUT" | grep -q 'LEAKME'; then
  fail "attribute value from before/after leaked into the workflow query output"
fi

# 3 — the cap logic is duplicated too (CAP, the threshold, and the
# "… N more (truncated)" notice). Extracting only the CAP literal and
# re-deriving the rest here would compare the script against a copy of itself,
# so instead run the workflow's own block: substitute the single `${{ }}`
# expression, stub `terraform show -json` to emit the fixture, and capture what
# the step writes to $GITHUB_OUTPUT. That makes the whole step the unit under
# test — threshold and notice wording included.
run_workflow_step() { # run_workflow_step <plan-json>
  local plan="$1" dir block
  dir="$(mktemp -d)"
  # shellcheck disable=SC2064  # expand dir now, it is local to this function
  trap "rm -rf '$dir'" RETURN

  printf '%s' "$plan" >"$dir/plan.json"

  # `terraform show -json <file>` is the step's only external dependency; the
  # stub ignores the arguments and emits the fixture. `environment` is the one
  # ${{ }} expression in the block.
  {
    printf 'terraform() { cat "%s"; }\n' "$dir/plan.json"
    printf 'GITHUB_OUTPUT="%s/out"\n' "$dir"
    printf '%s\n' "$RUN_BLOCK" | sed 's/\${{ inputs\.environment }}/test/g'
  } >"$dir/step.sh"

  # The block ends in `exit 0`, so run it in a subshell rather than sourcing.
  bash "$dir/step.sh" >/dev/null 2>&1

  [ -f "$dir/out" ] || return 1
  # Unwrap the `summary<<DELIM ... DELIM` heredoc the step appends.
  block="$(sed -e '1d' -e '$d' "$dir/out")"
  printf '%s' "$block"
}

printf '%s\n' "$RUN_BLOCK" | grep -q 'GITHUB_OUTPUT' || fail "workflow step no longer writes to GITHUB_OUTPUT (test harness stale)"

# Drive more resources than the cap through both copies and compare. The script
# caps at 50, so 80 crosses the threshold in both. Mirrors assertion 4 in
# test-drift-summary.sh.
BIG_PLAN="$(jq -n '{resource_changes: [range(80) | {address: ("authentik_group.g\(.)"), change: {actions: ["update"]}}]}')"
BIG_SCRIPT="$(printf '%s' "$BIG_PLAN" | "$SCRIPT")"
BIG_WORKFLOW="$(run_workflow_step "$BIG_PLAN")" || fail "workflow step produced no GITHUB_OUTPUT for the capped case"
[ "$BIG_WORKFLOW" = "$BIG_SCRIPT" ] || fail "capped output drifted for 80 resources:
workflow:
$BIG_WORKFLOW
script:
$BIG_SCRIPT"

# 4 — the same block below the cap, so the else-branch is covered too.
SMALL_WORKFLOW="$(run_workflow_step "$PLAN")" || fail "workflow step produced no GITHUB_OUTPUT for the fixture"
[ "$SMALL_WORKFLOW" = "$SCRIPT_OUT" ] || fail "uncapped step output drifted:
workflow:
$SMALL_WORKFLOW
script:
$SCRIPT_OUT"

# 5 — exactly CAP resources. This is the only input size where `-gt` and `-ge`
# disagree, so without it a flipped threshold passes both cases above: 80 is
# truncated either way, and the fixture is under the cap either way. At the
# boundary the correct behaviour is no truncation notice.
CAP_N="$(printf '%s\n' "$RUN_BLOCK" | sed -n 's/^[[:space:]]*CAP=\([0-9][0-9]*\)[[:space:]]*$/\1/p' | head -n 1)"
[ -n "$CAP_N" ] || fail "CAP not found in the workflow step"
EDGE_PLAN="$(jq -n --argjson n "$CAP_N" '{resource_changes: [range($n) | {address: ("authentik_group.g\(.)"), change: {actions: ["update"]}}]}')"
EDGE_SCRIPT="$(printf '%s' "$EDGE_PLAN" | "$SCRIPT")"
EDGE_WORKFLOW="$(run_workflow_step "$EDGE_PLAN")" || fail "workflow step produced no GITHUB_OUTPUT at the cap boundary"
[ "$EDGE_WORKFLOW" = "$EDGE_SCRIPT" ] || fail "output drifted at exactly CAP ($CAP_N) resources:
workflow:
$EDGE_WORKFLOW
script:
$EDGE_SCRIPT"
if printf '%s\n' "$EDGE_WORKFLOW" | grep -q 'truncated'; then
  fail "exactly CAP resources must not be reported as truncated"
fi

echo "PASS: deploy-terraform.yml <-> drift-summary.sh parity"

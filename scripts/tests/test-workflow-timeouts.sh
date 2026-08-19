#!/usr/bin/env bash
# A job without `timeout-minutes` inherits GitHub's 6-hour default. A hung step
# — a scanner waiting on a registry that never answers, a `docker pull` against
# a rate-limited host — then holds a runner for six hours before the run is
# marked failed. On self-hosted runners that is the whole queue; on hosted ones
# it is six hours of billed minutes for a result nobody waited for.
#
# The failure is invisible in review: nothing about a job *reads* wrong when the
# key is absent, and the job passes normally until the day something hangs. So
# it is asserted structurally instead — every job in every workflow declares its
# own ceiling.
#
# Jobs that only call a reusable workflow (`uses:` instead of `steps:`) are
# exempt, and not by choice: GitHub rejects `timeout-minutes` on a
# `workflow_call` job at parse time ("Unexpected value 'timeout-minutes'"). The
# ceiling for those lives in the called workflow's own jobs, which this test
# checks there. The exemption is derived from the job body rather than kept as a
# name list, so a job that later grows `steps:` is covered the moment it does.
#
# Parsed as YAML, not grepped: a `timeout-minutes` in a comment or in a `with:`
# block passed to an action would satisfy a text match while the job still runs
# uncapped.
#
# Run: scripts/tests/test-workflow-timeouts.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORKFLOWS="$REPO/.github/workflows"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -d "$WORKFLOWS" ] || fail "$WORKFLOWS not found"
command -v python3 >/dev/null 2>&1 || fail "python3 required to parse the workflow YAML"

# One parser pass reports every violation, so a run shows the whole list rather
# than surfacing them one re-run at a time.
ERRORS="$(
  python3 - "$WORKFLOWS" <<'PY'
import pathlib, sys, yaml

workflows = sorted(pathlib.Path(sys.argv[1]).glob("*.yml"))
if not workflows:
    print("no workflow files found")
    raise SystemExit(0)

checked = 0
exempt = 0

for path in workflows:
    with path.open() as fh:
        doc = yaml.safe_load(fh) or {}
    for name, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            print(f"{path.name}: job `{name}` is not a mapping")
            continue
        # A caller job delegating to a reusable workflow. `uses:` and `steps:`
        # are mutually exclusive at the job level, so this is unambiguous.
        if "uses" in job:
            exempt += 1
            continue
        checked += 1
        value = job.get("timeout-minutes")
        if value is None:
            print(
                f"{path.name}: job `{name}` has no `timeout-minutes` "
                "— it would inherit the 6-hour default"
            )
            continue
        # An expression is allowed (a caller-tunable ceiling is still a
        # ceiling); a literal has to be a positive number.
        if isinstance(value, str) and "${{" in value:
            continue
        if not isinstance(value, (int, float)) or isinstance(value, bool) or value <= 0:
            print(f"{path.name}: job `{name}`: `timeout-minutes` is {value!r}, expected a positive number")

# Counts ride out on the same stream, tagged, and are split off below. A
# second channel (stderr, a temp file) would have to survive the `$(...)`
# capture, and a temp file that fails to appear reads as "zero jobs checked"
# — a green run over nothing.
print(f"#counts {checked} jobs checked, {exempt} reusable-workflow callers exempt")
PY
)" || fail "could not parse the workflow YAML"

COUNTS="$(printf '%s\n' "$ERRORS" | sed -n 's/^#counts //p')"
ERRORS="$(printf '%s\n' "$ERRORS" | grep -v '^#counts ' || true)"

# The counts line is emitted unconditionally, so its absence means the parser
# died before the end — a partial list read as a clean run would be the same
# silent-green defect this file exists to catch.
[ -n "$COUNTS" ] || fail "the workflow parser did not run to completion"

if [ -n "$ERRORS" ]; then
  echo "$ERRORS" >&2
  fail "every job needs its own \`timeout-minutes\` (reusable-workflow callers excepted)"
fi

echo "PASS: every job declares timeout-minutes ($COUNTS)"

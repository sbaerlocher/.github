#!/usr/bin/env bash
# The pytest suites of the GitOps consumers ran only in a local `pre-push` hook,
# which is opt-in (`lefthook install`) and bypassed by `--no-verify`, web-UI
# edits and bot branches. `ci-gitops.yml` gained a `validate-python` job so those
# paths are covered by CI instead.
#
# This asserts the three parts that have to hold together, because each is silent
# when it breaks:
#
#   1. The inputs exist with the right type and default. `enable-python-tests`
#      defaults to `false` — unlike every other `enable-*` here — so existing
#      callers do not get a job they never asked for and a repo without Python
#      tests does not turn red on upgrade.
#   2. The job exists, is gated on that input, and interpolates no `inputs.*`
#      into a `run:` body (same class of hole as test-workflow-input-injection.sh
#      closes for the other workflows).
#   3. `summary.needs` lists the job. `summary` runs with `if: always()` and is
#      what the branch protection reads; a job missing from `needs` still runs,
#      but its red never reaches the gate — green PR, failing tests.
#
# Assertions run against the parsed YAML, not the raw text: a `grep` for
# `validate-python` is satisfied by a mention in a comment, which would let this
# test pass over a workflow that lost the job.
#
# Run: scripts/tests/test-validate-python-input.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORKFLOW="$REPO/.github/workflows/ci-gitops.yml"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -f "$WORKFLOW" ] || fail "ci-gitops.yml not found — update this test if it was renamed"
command -v python3 >/dev/null 2>&1 || fail "python3 required to parse the workflow YAML"

# One parser pass reports every violation it finds, so a run shows the whole list
# instead of surfacing them one re-run at a time.
ERRORS="$(
  python3 - "$WORKFLOW" <<'PY'
import sys, yaml

with open(sys.argv[1]) as fh:
    doc = yaml.safe_load(fh) or {}

errors = []

# YAML 1.1 resolves an unquoted `on:` key to the boolean True.
triggers = doc.get("on", doc.get(True)) or {}
inputs = (triggers.get("workflow_call") or {}).get("inputs") or {}
jobs = doc.get("jobs") or {}

# 1 — the inputs. Default is compared after normalising, because the YAML
# scalars `false` and `'false'` mean the same thing to a caller here.
EXPECTED = {
    "enable-python-tests": ("boolean", False),
    "python-test-paths": ("string", "scripts"),
    "python-test-requirements": ("string", "pytest pyyaml"),
}

def norm(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, str) and value.lower() in ("true", "false"):
        return value.lower() == "true"
    return value

for name, (want_type, want_default) in EXPECTED.items():
    spec = inputs.get(name)
    if spec is None:
        errors.append(f"input `{name}` is missing")
        continue
    if spec.get("type") != want_type:
        errors.append(f"input `{name}`: type is {spec.get('type')!r}, expected {want_type!r}")
    if norm(spec.get("default")) != want_default:
        errors.append(
            f"input `{name}`: default is {spec.get('default')!r}, expected {want_default!r}"
        )
    # `required: false` must be explicit. Omitting it leaves the default to
    # GitHub rather than stating the contract at the call site.
    if spec.get("required") is not False:
        errors.append(f"input `{name}`: must be declared `required: false`")
    if not (spec.get("description") or "").strip():
        errors.append(f"input `{name}`: needs a description")

# Both string inputs are expanded unquoted in the shell, so they carry the same
# warning as `fleet-paths`. The sentence is the contract for callers; without it
# the next reader has no reason not to wire an event value through.
WARNING = "never event-controlled data"
for name in ("python-test-paths", "python-test-requirements"):
    spec = inputs.get(name) or {}
    if WARNING not in (spec.get("description") or ""):
        errors.append(f"input `{name}`: description must warn {WARNING!r}")

# 2 — the job.
job = jobs.get("validate-python")
if job is None:
    errors.append("job `validate-python` is missing")
else:
    if "inputs.enable-python-tests" not in str(job.get("if", "")):
        errors.append("job `validate-python`: `if:` must gate on inputs.enable-python-tests")

    steps = job.get("steps") or []
    checkout = next(
        (s for s in steps if str(s.get("uses", "")).startswith("actions/checkout@")),
        None,
    )
    if checkout is None:
        errors.append("job `validate-python`: no actions/checkout step")
    elif (checkout.get("with") or {}).get("persist-credentials") is not False:
        errors.append("job `validate-python`: checkout needs `persist-credentials: false`")

    # The actual hardening: a caller-supplied value substituted into a `run:`
    # body is text before the shell sees it, so it can close a quote and execute.
    # Values must travel via `env:` and be referenced as shell variables.
    for step in steps:
        if "inputs." in str(step.get("run", "")):
            errors.append(
                f"job `validate-python`: step {step.get('name', '?')!r} "
                "interpolates inputs.* into a run: body — pass it via env:"
            )

# 3 — the gate. `needs` accepts a string or a list; both are checked so a
# single-entry rewrite cannot slip past.
summary = jobs.get("summary") or {}
needs = summary.get("needs") or []
if isinstance(needs, str):
    needs = [needs]
if "validate-python" not in needs:
    errors.append("job `summary`: `needs` must include validate-python")

for error in errors:
    print(error)
PY
)" || fail "could not parse $WORKFLOW"

if [ -n "$ERRORS" ]; then
  echo "$ERRORS" >&2
  fail "ci-gitops.yml: validate-python is not wired up correctly"
fi

echo "PASS: ci-gitops.yml wires validate-python (inputs, job, summary gate)"

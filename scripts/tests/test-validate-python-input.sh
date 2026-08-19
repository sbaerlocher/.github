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
#   2. The pytest step exists and is gated on that input, in a job with a
#      credential-less checkout. The `inputs.*`-in-a-`run:`-body hole is *not*
#      re-checked here: `ci-gitops.yml` is in the MIGRATED list of
#      test-workflow-input-injection.sh, which covers every job in the file
#      rather than this one, so a step added here later stays guarded.
#   3. The enforce step reads the pytest outcome. The validations run as steps
#      with `continue-on-error`, so a red pytest ends the job green unless the
#      final `always()` step re-raises it; an outcome missing there still runs
#      the tests, but their red never reaches the gate — green PR, failing tests.
#
# Assertions run against the parsed YAML, not the raw text: a `grep` for
# `python` is satisfied by a mention in a comment, which would let this test
# pass over a workflow that lost the step.
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
    # Strict by default: an empty collection is a configuration error unless the
    # caller opts out. Flipping this default would turn a suite that stopped
    # being collected back into a silent green.
    "allow-no-python-tests": ("boolean", False),
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

# 2 — the pytest step. The validations share one job (billing rounds every job
# up to a full minute, so eight short jobs cost eight minutes), which makes the
# step — not a job — the unit to assert.
steps = [s for job in jobs.values() for s in (job.get("steps") or [])]
pytest_step = next((s for s in steps if s.get("id") == "python"), None)
if pytest_step is None:
    errors.append("step `python` (pytest) is missing")
else:
    if "inputs.enable-python-tests" not in str(pytest_step.get("if", "")):
        errors.append("step `python`: `if:` must gate on inputs.enable-python-tests")
    # Without this the step cannot fail the job on its own, and the enforce
    # step checked below is what turns its recorded failure back into red.
    if pytest_step.get("continue-on-error") is not True:
        errors.append("step `python`: must set `continue-on-error: true`")

owner = next(
    (job for job in jobs.values()
     if any(s.get("id") == "python" for s in (job.get("steps") or []))),
    None,
)
if owner is not None:
    checkout = next(
        (s for s in (owner.get("steps") or [])
         if str(s.get("uses", "")).startswith("actions/checkout@")),
        None,
    )
    if checkout is None:
        errors.append("the job running pytest has no actions/checkout step")
    elif (checkout.get("with") or {}).get("persist-credentials") is not False:
        errors.append("the pytest job: checkout needs `persist-credentials: false`")

# 3 — the gate. `continue-on-error` above means the job ends green on its own,
# so the final always()-step has to read the pytest outcome and re-raise it.
enforce = next((s for s in steps if s.get("name") == "Enforce validation results"), None)
if enforce is None:
    errors.append("step `Enforce validation results` is missing")
else:
    if "always()" not in str(enforce.get("if", "")):
        errors.append("step `Enforce validation results`: must run with `if: always()`")
    if "steps.python.outcome" not in str(enforce.get("env") or {}):
        errors.append(
            "step `Enforce validation results`: env must read steps.python.outcome"
        )

for error in errors:
    print(error)
PY
)" || fail "could not parse $WORKFLOW"

if [ -n "$ERRORS" ]; then
  echo "$ERRORS" >&2
  fail "ci-gitops.yml: validate-python is not wired up correctly"
fi

echo "PASS: ci-gitops.yml wires validate-python (inputs, step, enforce gate)"

#!/usr/bin/env bash
# `continue-on-error: true` converts a step's failure into a recorded outcome
# instead of a red job. That is the right primitive when later steps have to run
# regardless — a scanner should not stop the report that summarises it — but on
# its own it is a silent green: the step failed, the job passed, and nothing in
# the run says so.
#
# The pattern only holds when the recorded outcome is read back. That needs two
# things, and neither is inferable from the other:
#
#   a) The step has an `id`. Without one, `steps.<id>.outcome` does not exist
#      and the failure is not merely unreported — it is unreachable. This is the
#      hole that made security-containers.yml structurally unable to fail: three
#      of its six continue-on-error steps had no id at all.
#
#   b) Some later step in the same job references that id. An id nobody reads is
#      the same silent green with extra ceremony.
#
# Rule (b) accepts any consuming step, not only an `always()` one. Both shapes
# are legitimate and mean different things:
#
#   An `always()` consumer is the gate for a step whose failure must not stop
#   the job — the enforce step in security-containers.yml and security-config.yml.
#   Use it when the outcome has to be read even if something upstream died.
#
#   A plain consumer is the shape for a deliberate expected-failure assertion:
#   the smoke jobs in test-actions-dde.yml run an action that is *supposed* to
#   fail and then assert `steps.project.outcome == 'failure'`. Requiring
#   `always()` there would be wrong — if an earlier setup step broke, the
#   assertion is meaningless and should be skipped, not evaluated against a
#   failure it did not cause.
#
# What both exclude is the case this guards: nobody reads it.
#
# Parsed as YAML, not grepped: a `steps.foo.outcome` inside a comment satisfies
# a text search while the gate it describes has been deleted.
#
# Run: scripts/tests/test-continue-on-error-enforced.sh
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

ERRORS="$(
  python3 - "$WORKFLOWS" <<'PY'
import pathlib, sys, yaml

# Steps that predate this guard and are not fixed here — narrowing the PR that
# introduced the check to the workflow it was written for. Each entry is
# "<file>::<job>::<step name>", so a rename surfaces as a stale-entry error
# below rather than silently widening the carve-out.
#
# This is a debt list, not a design: every entry is a step whose failure is
# currently invisible. They fall into two shapes — best-effort uploads
# (Codecov, SARIF, artifacts) where the argument for exempting them is real but
# belongs written at the call site, and setup steps (security-deps.yml's
# language toolchains) where it is not obviously right at all. Both want a
# separate change per file.
KNOWN = {
    "ci-go.yml::test-and-lint::Upload coverage to Codecov",
    "ci-go.yml::security-scan::Upload SARIF file",
    "ci-js.yml::security-scan::Cache dependencies",
    "ci-js.yml::security-scan::Upload SARIF file",
    "ci-terraform.yml::validation::Upload Trivy Results (Artifact)",
    "e2e-dde.yml::e2e-dde::Show running services",
    "release-docker.yml::docker-build::Scan image for vulnerabilities",
    "release-docker.yml::docker-build::Upload Trivy SARIF",
    "release-npm.yml::github-release::Download SBOM artifact",
    "security-config.yml::config-scan::Upload Trivy results to GitHub Security",
    "security-config.yml::config-scan::Upload Trivy results",
    "security-deps.yml::dependency-scan::Setup Go",
    "security-deps.yml::dependency-scan::Setup Node.js",
    "security-deps.yml::dependency-scan::Setup Python",
    "security-sbom.yml::sbom-report::Download SBOM",
}

workflows = sorted(pathlib.Path(sys.argv[1]).glob("*.yml"))
seen_known = set()
checked = 0

def truthy(value):
    # `continue-on-error: ${{ ... }}` is conditional, so it can still fail the
    # job and is not the silent-green shape. Only an unconditional true is.
    return value is True or (isinstance(value, str) and value.strip().lower() == "true")

for path in workflows:
    with path.open() as fh:
        doc = yaml.safe_load(fh) or {}
    for job_name, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        steps = [s for s in (job.get("steps") or []) if isinstance(s, dict)]
        coe = [s for s in steps if truthy(s.get("continue-on-error"))]
        if not coe:
            continue

        # Everything a later step could read an outcome through: the `if:`
        # guard, the `env:` block, the `run:` body and an action's `with:`.
        consumers = "".join(
            str(s.get("if", "")) + str(s.get("env") or "")
            + str(s.get("run") or "") + str(s.get("with") or "")
            for s in steps
        )

        for step in coe:
            label = f"{path.name}::{job_name}::{step.get('name', '<unnamed>')}"
            known = label in KNOWN
            if known:
                seen_known.add(label)
            checked += 1

            step_id = step.get("id")
            if not step_id:
                if not known:
                    print(f"{label}: `continue-on-error: true` without an `id` "
                          "— its failure cannot be read back by any step")
                continue
            if f"steps.{step_id}." not in consumers:
                if not known:
                    print(f"{label}: id `{step_id}` is never read as "
                          f"steps.{step_id}.outcome by another step in this job "
                          "— the failure is recorded and discarded")
                continue
            # A listed step that now passes has had its debt paid; the entry
            # must go, or the list keeps protecting nothing.
            if known:
                print(f"{label}: is in KNOWN but now satisfies the rule — drop the entry")

for stale in sorted(KNOWN - seen_known):
    print(f"KNOWN lists `{stale}`, which no longer exists — drop or update the entry")

print(f"#counts {checked} continue-on-error steps, {len(KNOWN)} grandfathered")
PY
)" || fail "could not parse the workflow YAML"

COUNTS="$(printf '%s\n' "$ERRORS" | sed -n 's/^#counts //p')"
ERRORS="$(printf '%s\n' "$ERRORS" | grep -v '^#counts ' || true)"

# Emitted unconditionally, so its absence means the parser died early and a
# short list was read as a clean run.
[ -n "$COUNTS" ] || fail "the workflow parser did not run to completion"

if [ -n "$ERRORS" ]; then
  echo "$ERRORS" >&2
  fail "a continue-on-error step is not enforced (needs an \`id\` read back by a later step)"
fi

echo "PASS: every continue-on-error step is read back ($COUNTS)"

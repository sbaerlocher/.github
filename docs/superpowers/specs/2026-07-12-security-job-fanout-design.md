# Security reusables: reduce job fan-out against per-minute rounding

**Date:** 2026-07-12
**Type:** Refactor
**Notion:** https://app.notion.com/p/39abf097036e8133b4b4d95db8b56bee
**Path:** non-trivial · **Effort:** M · **Priority:** P2

## Problem

GitHub rounds every job up to a full billed minute. The four shared security
reusables split into many separate jobs, each with its own runner spin-up,
checkout and minute rounding. Individual scan jobs sometimes run only 6–13 s but
are each rounded up to a full minute, so the split is almost pure rounding tax.
Measured at roughly 902 billable min/mo fleet-wide (367 secrets + 535
deps/config/containers).

## Goal

Merge jobs that need no permission isolation of their own into ONE job with
sequential steps. Make `security-report` a final step instead of its own job.

## Changes per workflow

| Workflow                  | Before | After                                                                                                        | Runners saved |
| ------------------------- | ------ | ------------------------------------------------------------------------------------------------------------ | ------------- |
| `security-secrets.yml`    | 4 jobs | `gitleaks` (isolated, `pull-requests:read`) + `secret-scan` (trufflehog + pattern + report, `contents:read`) | 2             |
| `security-deps.yml`       | 5 jobs | 1 job `dependency-scan`, steps keep their `if:` guards                                                       | 4             |
| `security-containers.yml` | 4 jobs | 1 job `container-scan`                                                                                       | 3             |
| `security-config.yml`     | 5 jobs | 1 job `config-scan`                                                                                          | 4             |

## Trade-off (not to be waved away)

For `secrets` the split is partly deliberate: `gitleaks` runs with a scoped
per-job `pull-requests: read` (least privilege, documented in REVIEW.md and
CHANGELOG.md — gitleaks-action v3 enumerates PR commits via the pulls API).
**Decision: stay conservative.** `gitleaks` remains its own job. `trufflehog` +
`pattern-detection` + `report` move into one `secret-scan` job with only
`contents: read`. Least privilege stays clean and this saves 2 runners instead
of 3.

For `deps`/`containers`/`config`, all jobs already share the workflow-level
permissions and differ only in their `if:` conditions. Merging each into a
single job is permission-neutral.

## Mechanics

- **Merged job = 1 checkout + sequential steps.** Every step keeps its original
  job `if:` condition, now as a step `if:`
  (e.g. `if: inputs.language == 'go' || inputs.language == 'multi'`).
- **Setup union:** the deps job needs Go, Node and Python setup, each behind the
  matching step `if:`. The language guards prevent unnecessary installs.
- **`security-report` becomes the final step.** Job result refs
  (`needs.X.result`) do not work inside a single job. Replacement: step `id:`
  plus `steps.<id>.outcome` in the report table. Every scan step whose result
  belongs in the report gets an `id:`.
- **`continue-on-error`:** steps now run sequentially, so a step with `exit 1`
  would abort the report step. The existing jobs already use
  `|| true`/`continue-on-error` widely. Every scan step that could end fatally
  but whose report must still run gets `continue-on-error: true`. The report
  step itself runs with `if: always()`.
- **`timeout-minutes`:** merged job = sum/union of the old step timeouts (an
  upper bound, no need to be stingy).

### Report reference mapping

Instead of `needs.<job>.result`, use `steps.<id>.outcome`:

- secrets `secret-scan`: `trufflehog` + `pattern-detection` step outcomes;
  gitleaks stays its own job and the report references `needs.gitleaks.result`
  (keep `needs: [gitleaks]` on secret-scan, only for the report row).
- deps `dependency-scan`: `dependency-review`, `go-audit`, `js-audit`,
  `python-audit` step outcomes.
- containers `container-scan`: `trivy`, `grype`, `image-analysis`.
- config `config-scan`: `trivy-config`, `terraform`, `kubernetes`, `ansible`.

A step skipped by its `if:` has outcome `skipped`, which is correct in the
table.

## Breaking change

Merging jobs changes the status-check context names. The old contexts
(`Audit Go`, `Scan with Trivy`, `Create Report`, …) disappear and are replaced
by a single `<scan job name>` context. Branch-protection and ruleset anchors in
consumer repos that point at the old names will break.

**Handling:**

1. Cut a new date tag (no `@main` for consumers).
2. Add a `### ⚠ BREAKING` heading to that tag's CHANGELOG entry: affected
   workflows, new job names and the migration step "repoint
   ruleset/branch-protection required-status-check anchors at the new context
   names".
3. Update the job-count references in AGENTS.md and README (24 workflows stays,
   but job counts and descriptions need adjusting).

## New job names (status-check contexts)

- `security-secrets.yml`: `Scan with Gitleaks` (unchanged) + `Scan Secrets`
- `security-deps.yml`: `Scan Dependencies`
- `security-containers.yml`: `Scan Container Image`
- `security-config.yml`: `Scan Configuration`

## Testing

- `actionlint` on the 4 changed files (syntax + expression checks).
- Check the YAML expression syntax manually (step outcome refs).
- **No** consumer live test in this session (that would need a tag push).
  Flagged as a manual step: after cutting the tag, test 1–2 consumer repos
  against the new tag before rolling it out broadly.

## Scope boundaries (skipped)

- A matrix-based merge — would still fan out to N runners, which defeats the
  purpose.
- `security-code.yml` / `security-sbom.yml` — outside the card scope.
- No change to the behaviour of the scans themselves, only to job topology.

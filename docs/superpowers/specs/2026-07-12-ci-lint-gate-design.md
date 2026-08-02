# Gate lint/fast checks ahead of heavy jobs in the ci-\* reusables

**Date:** 2026-07-12
**Type:** Refactor
**Notion:** https://app.notion.com/p/39abf097036e81d099f6c430062282f5
**Path:** non-trivial · **Effort:** M · **Priority:** P2

## Problem

In the shared `ci-*.yml` reusables, expensive jobs (security scan, CodeQL,
Terraform plan/Trivy, ansible-lint, Helm render/kubeconform) partly run in
parallel with, or independently of, a cheap lint/format/validate. A lint error
does not stop the expensive job early, which wastes minutes. From the minutes
audit (measure 2): failed and cancelled runs pulled roughly 433 min/mo of
compute fleet-wide.

## Goal

Run expensive jobs only AFTER a fast gate (`needs:`). A lint error aborts early
instead of letting an expensive job run in parallel and be discarded anyway.

## Changes per workflow

| Workflow           | Change                                                                                                                  |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| `ci-go.yml`        | None — `security-scan` + `codeql-analysis` are already gated (`needs: [setup, test-and-lint, test-and-lint-postgres]`). |
| `ci-js.yml`        | None — `security-scan` is already gated (`needs: [setup, quality-and-test]`).                                           |
| `ci-terraform.yml` | `lint` + `trivy` get `needs: validation`.                                                                               |
| `ci-ansible.yml`   | `lint` + `yamllint` get `needs: validation`.                                                                            |
| `ci-gitops.yml`    | All 6 non-gate jobs get `needs: [validate-yaml]` + a guard `if:`.                                                       |

## Two needs patterns

**terraform / ansible — plain `needs`:** the `validation` job is unconditional
(no `if:`). `needs: validation` is enough: if `validation` fails, the dependent
jobs are skipped. `lint` keeps its existing `if: inputs.enable-*`.

**gitops — `needs` + an always() guard:** the gate job `validate-yaml` is
conditional (`if: inputs.enable-yaml-lint`). Plain `needs` would also skip the
dependent jobs when the gate is _disabled_. Guard:

```yaml
needs: [validate-yaml]
if: >-
  always() && !failure() && !cancelled()
  && inputs.enable-<own-flag>
```

This runs when the gate is **success** OR **skipped**, and blocks only on gate
**failure**. Every job keeps its own `enable-*` in the same `if:`.

Affected gitops jobs (all except `validate-yaml` and `summary`):
`validate-fleet-configs`, `validate-gitrepo`, `validate-helm`,
`validate-helm-template`, `validate-kubernetes`, `check-documentation`.
`summary` keeps its existing `needs: [...]` + `if: always()`.

## go/js: why no change

`dependency-review` in ci-go (line 528) and ci-js (line 521) has no `needs:`,
so it runs in parallel. It is, however, **not a heavy job**: a plain
`dependency-review-action`, PR-only plus public-only, with no build or scan
compute. The card targets the expensive jobs (security scan, CodeQL), which are
already gated. Gating `dependency-review` would only add wall-clock time for an
already cheap check, so it is deliberately left ungated (YAGNI).

## Status checks / BREAKING

**No job names change**, only `needs:` (plus the `if:` guards in gitops).
Status-check context names stay stable, so **no** ruleset or branch-protection
anchor migration is needed. That makes this **not** a breaking change in the
CHANGELOG sense, so a regular date tag is sufficient and no `⚠ BREAKING` is
required.

Behaviour change (non-breaking, worth documenting): a run that previously showed
a heavy job independently as `failure` now shows it as `skipped` when the gate
fails first. Successful runs get slightly slower because they are sequential
(gate first, then heavy) — a trade-off against the minutes saved on failing
runs.

## Testing

- `actionlint` on ci-terraform, ci-ansible, ci-gitops (syntax, needs references
  and expression guards).
- Verify that the go/js heavy jobs remain fully gated (read-only).
- **No** consumer live test in this session (that would need a tag push). Manual
  step: test in 1–2 consumer repos after cutting the tag.

## Scope boundaries (skipped)

- A dedicated `gate` job in gitops — a larger rebuild, and the `validate-yaml`
  name would change (more BREAKING). `needs` plus a guard is the smaller change.
- go/js code changes — the heavy jobs are already gated.
- No change to job logic, only to the dependency topology.

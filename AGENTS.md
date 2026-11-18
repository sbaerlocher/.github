# AGENTS.md

Reusable GitHub Actions workflows, composite actions and Renovate presets for
every `sbaerlocher` repository. Every change here reaches all consumer repos on
their next tag bump, so treat each edit as a fleet-wide change.

## Commands

`just lint` and `just test` are the gate: `pull-request.yml` runs both, so a
local failure is a CI failure. Setup and the actionlint fallback order are in
[CONTRIBUTING.md](./CONTRIBUTING.md).

`just fmt` reflows Markdown tables repo-wide. Keep its output out of unrelated
changes.

## Layering

Consumer repos split CI into three layers:

1. **Repo workflow**: only `on:`, `permissions:` and `uses:`. A thin trigger
   hull without multi-line `run:` steps.
2. **Reusable workflow** (`.github/workflows/`): owns the pipeline logic and
   exposes it through `inputs:`, `outputs:` and `secrets:`.
3. **Composite action** (`.github/actions/`): owns a tool-bootstrap step once
   the same shell logic appears in more than one reusable.

Logic that repeats across reusables moves into a composite action.

## Reusable workflow contract

Every workflow with a `workflow_call` trigger exposes:

- `runner` (default `ubuntu-latest`), used by every `runs-on:`.
- `cancel-in-progress` (CI/Security/E2E default `true`, Deploy/Release/Ops
  default `false`, AI per workflow) and `concurrency-suffix` (default empty).

The reusable owns `concurrency:`. Consumer workflows calling it set none for the
same group. Before adding or changing either input, read
[docs/workflow-conventions.md](./docs/workflow-conventions.md).

Further rules:

- File names: `ci-`, `security-`, `deploy-`, `release-`, `ops-`, `ai-`, `e2e-`
  prefix for reusables. `test-*.yml` is an internal self-test for one action,
  filtered by workflow-level `paths:` and never a required check.
- `name:` spells the intent out (`Continuous Integration`, not `CI`).
- Inputs and secrets carry a type and a `description:`; optional inputs have a
  default that keeps existing callers unchanged.
- Internal workflows (no `workflow_call`) keep naming their runner directly.

## Action pinning

Every `uses:` points to a full 40-character commit SHA with the version tag as
a trailing comment:

```yaml
uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
```

Renovate updates SHA and comment together. A mismatched comment is a bug.

Sibling actions of this repo are referenced by full path and date tag
(`sbaerlocher/.github/.github/actions/<name>@<YYYY-MM-DD>`), also from inside
reusables and other actions. `uses: ./...` resolves against the caller's
workspace, not this repo
([actions/runner#2185](https://github.com/actions/runner/issues/2185)).
Two `./` forms are intended, both in internal workflows that run on this
repo's own checkout:

- `pull-request.yml` and `weekly-security.yml` call this repo's reusables via
  `uses: ./.github/workflows/<file>`, so PR checks run the copy in the PR.
  Keep them local; a date tag or SHA would test the released version.
- `test-actions-dde.yml` checks this repo out first and uses
  `./.github/actions/...`. Its `smoke-project-*` jobs still run the tagged
  `setup-dde`, because `project/action.yml` pins `setup-dde` by date tag.

## Versioning and breaking changes

`merge.yml` tags every push to `main` with the UTC date (`YYYY-MM-DD`). The
day's tag moves to the newest commit until the day ends, then stays fixed.
There are no semver tags. Consumers pin a date tag; `@main` is only for
testing a change from a consumer repo before merge.

A breaking change (input or output removed, input made required, input type or
default value changed, default behaviour changed) gets a `### ⚠ BREAKING` heading in that day's
`CHANGELOG.md` entry, naming the workflow and a one-line migration step. That
entry is the deprecation notice consumers scan before bumping.

`changelog.yml` fails a PR titled `feat`, `fix`, `perf`, `refactor` or with
`!` that touches `.github/workflows/`, `.github/actions/` or a
`renovate-*.json` preset without a `CHANGELOG.md` change. It also fails any PR
whose title is not a Conventional Commits subject with a known type.

## Required checks

A workflow that provides a required status check carries no workflow-level
`paths` / `paths-ignore`: a skipped workflow never reports, and the PR stays
`BLOCKED`. Filter at job level instead, with a `changes` job and one
aggregating `status` job as the only required check. Pattern and fail-open
rules: [docs/workflow-conventions.md](./docs/workflow-conventions.md#required-checks-and-path-filters).

## Platform constraints

A workflow that only works on Linux says so in its `runner` description. Today
these are `e2e-dde.yml`, `e2e-docker.yml`, `release-docker.yml`,
`security-config.yml` and `security-secrets.yml`. The test is what the steps
invoke (`docker`, `apt-get`, a socket mount), not whether an action is a
container action.

## Renovate presets

`renovate-*.json` at the root are presets consumers extend. This repo's own
config is the root `renovate.json` only, and it extends its own presets with
`#main`. Before editing any preset, read
[docs/renovate-presets.md](./docs/renovate-presets.md).

## Drift guards in `just test`

- `test-workflow-counts.sh`: the reusable/internal counts in `README.md` match
  `.github/workflows/`. Update the README line when adding or removing a
  workflow.
- `test-workflow-input-injection.sh`: caller values reach `run:` through
  `env:`, never as `${{ inputs.* }}` in the script body or an unquoted heredoc.
- `test-github-env-guards.sh`: caller values written to `$GITHUB_ENV` are
  validated in the same step, aborting on bad input.
- `test-workflow-timeouts.sh`: every job with `steps:` sets `timeout-minutes`.
- `test-continue-on-error-enforced.sh`: a `continue-on-error` step has an `id`
  and its outcome is read back later.

Read the failing test's header comment before changing a test to pass.

## Review

`REVIEW.md` holds the review rules that `ai-claude-review.yml` applies to PRs
in this repo (wired in `pull-request.yml`).

## More docs

- Before changing `runner`, concurrency, path filters or the dde actions:
  [docs/workflow-conventions.md](./docs/workflow-conventions.md).
- Before changing a `renovate-*.json` preset or `renovate.json`:
  [docs/renovate-presets.md](./docs/renovate-presets.md).
- Consumer-facing catalogue and usage: [README.md](./README.md).

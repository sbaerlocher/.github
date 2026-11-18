# Workflow conventions

Reference for anyone adding or changing a reusable workflow or composite action
in this repo. Read it before touching the `runner` input, concurrency, path
filters or the dde actions.

## Runner input

```yaml
inputs:
  runner:
    type: string
    required: false
    default: 'ubuntu-latest'
    description: >-
      Single runner label for all jobs in this workflow (e.g.
      `ubuntu-latest`, `self-hosted`). Runner groups and multi-label
      selectors are not supported.
```

Every `runs-on:` reads `${{ inputs.runner }}`. `runs-on` sits in the called
workflow and a caller cannot override it, so without this input no consumer
reaches a self-hosted runner.

- **Single label only.** The input is interpolated as one string. The sequence
  form (`[self-hosted, linux, x64]`) and the `group:` form need `fromJSON()`. A
  runner-group name is matched as a label no runner carries, and the job waits
  until it times out instead of failing.
- **Workflow-wide.** One label for all jobs of a reusable. Add a second input
  only once a consumer needs per-job routing.
- **Platform constraints** go into the `runner` description, since the input
  removed the structural `ubuntu-latest` guarantee.

## Concurrency inputs

```yaml
inputs:
  cancel-in-progress:
    type: boolean
    required: false
    default: <per-workflow-default> # CI/security/e2e: true; deploy/release/ops: false
    description: Cancel in-progress runs in the same group.
  concurrency-suffix:
    type: string
    required: false
    default: ''
    description: Suffix appended as `-<suffix>` to the concurrency group.
```

```yaml
concurrency:
  group: >-
    <base-group>${{
      inputs.concurrency-suffix != '' && format('-{0}', inputs.concurrency-suffix) || ''
    }}
  cancel-in-progress: ${{ inputs.cancel-in-progress }}
```

| Category             | Default `cancel-in-progress` | Override when                                                                                          |
| -------------------- | ---------------------------- | ------------------------------------------------------------------------------------------------------ |
| CI, Security, E2E    | `true`                       | every matrix leg must finish (e.g. compliance reports)                                                 |
| Deploy, Release, Ops | `false`                      | drift or scan runs where the latest invocation supersedes the older                                    |
| AI                   | per workflow                 | `ai-claude-review.yml` defaults to `true`, `ai-claude.yml` to `false`; a new `ai-*.yml` states its own |

`concurrency-suffix` is for a caller that invokes the same reusable from
several modes or matrix legs that must run in parallel, e.g.
`concurrency-suffix: drift` beside a deploy job calling `deploy-terraform.yml`.

### Base group

- **Caller-isolated**: `${{ github.workflow }}-${{ github.ref }}`. Under
  `workflow_call`, `github.workflow` is the caller's name, so each caller gets
  its own group. Default for new reusables.
- **Resource-locked**: built from inputs, e.g.
  `${{ inputs.project-name }}-terraform-${{ inputs.environment }}` in
  `deploy-terraform.yml` or `${{ inputs.project-name }}-${{ inputs.environment }}`
  in `ops-drift-issue.yml`. Use it when the workflow guards a shared resource
  (Terraform state, an issue list) that must serialise across all callers.

### Why the reusable owns it

A consumer that wraps a reusable in its own `concurrency:` block for the same
scope puts two limiters in series. That caused queue pile-ups and surprise
cancellations. The consumer picks policy through the two inputs instead.

## Required checks and path filters

A workflow-level `paths` / `paths-ignore` under `on.pull_request` skips the
whole workflow on a match. If that workflow provides a required check, the
check never reports and the PR stays `BLOCKED`.

To save CI on docs-only PRs, filter at job level:

1. A `changes` job diffs base against head (`git diff --name-only`) and outputs
   `code=true|false`. It needs the base commit: use `fetch-depth: 0` or fetch
   the base SHA. Any diff error yields `code=true`.
2. Expensive jobs run with `if: needs.changes.outputs.code == 'true'`.
3. One aggregating `status` job (`All Checks Passed`) is the only required
   check. It needs `changes` and every gated job, runs with
   `if: ${{ !cancelled() }}`, and passes only if `changes` is `success` and no
   other needed job is `failure` or `cancelled`. `skipped` passes for gated
   jobs, never for `changes`: a dead `changes` job would otherwise turn the run
   green with nothing tested.

Jobs that should run on docs-only PRs too (e.g. the Claude review) do not
depend on `changes`.

`test-*.yml` self-tests keep their workflow-level `paths:` and are never
required checks.

## dde actions

`setup-dde` downloads the dde binary from
[`whatwedo/dde`](https://github.com/whatwedo/dde) releases, verifies it against
`checksums.txt`, and optionally installs `mkcert` and runs
`dde system:install` as the runner user. dde escalates with passwordless sudo
per step. Wrapping the whole call in `sudo` leaves `~/.dde/data/` root-owned
and breaks the following unprivileged `dde project:*` calls.

`project` wraps `setup-dde` plus one `dde project:<command>` (default `up`).
`system-install` and `wait-url` apply only to `up` and are ignored otherwise,
so callers pass them unconditionally.

Composite actions have no `post:` hook. Cleanup is an explicit `if: always()`
step in the consumer, usually `project` with `command: down`.

`test-actions-dde.yml` covers `setup-dde` directly in its `smoke-setup-dde`
matrix. Its `smoke-project-*` jobs use the tagged `setup-dde` via the full
path, so a `setup-dde` change is validated through `project` only after the
next date tag.

# `sbaerlocher/.github/.github/actions/project-up`

Bring a [whatwedo dde](https://github.com/whatwedo/dde) project up on a
GitHub Actions runner in one step. Installs the dde CLI, runs
`dde system:install`, executes `dde project:up` in your project directory,
and (optionally) waits for an HTTP endpoint to respond before handing
control back to your workflow.

For setup-only (no `system:install`, no `project:up`) use the sibling
[`setup-dde`](../setup-dde/) action.

## Usage

Pick the most recent date tag from
<https://github.com/sbaerlocher/.github/tags> (used as `<TAG>` below).

### Minimal — bring the project at the repo root up

```yaml
- uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
- uses: sbaerlocher/.github/.github/actions/project-up@2026-04-28
- run: dde project:exec composer test:e2e
- if: always()
  run: dde project:down
```

### With a wait-for-ready URL

```yaml
- uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
- uses: sbaerlocher/.github/.github/actions/project-up@2026-04-28
  with:
    wait-url: https://myproject.test/healthz
    wait-timeout: '180'
- run: npm run test:e2e
- if: always()
  run: dde project:down
```

### Project lives in a subdirectory

```yaml
- uses: sbaerlocher/.github/.github/actions/project-up@2026-04-28
  with:
    working-directory: ./apps/web
```

## Inputs

| Input               | Default        | Description                                                              |
|---------------------|----------------|--------------------------------------------------------------------------|
| `version`           | `latest`       | dde version (`v2.0.0-alpha.5`, `2.0.0-alpha.5`, or `latest`).            |
| `working-directory` | `.`            | Directory with `.dde/config.yml`. Fails fast if missing.                 |
| `install-mkcert`    | `true`         | Install `mkcert` (+ `libnss3-tools` on Linux) for local TLS certs.       |
| `system-install`    | `true`         | Run `dde system:install` (host setup). `'false'` skips it.               |
| `wait-url`          | `""`           | Poll this URL until 2xx/3xx (TLS errors ignored). Empty disables.        |
| `wait-timeout`      | `180`          | Maximum seconds to wait for `wait-url` to respond.                       |
| `github-token`      | `github.token` | Token for the GitHub API call that resolves `latest`.                    |
| `repository`        | `whatwedo/dde` | Source repository. Override for forks or staging mirrors.                |

## Outputs

| Output        | Description                                              |
|---------------|----------------------------------------------------------|
| `version`     | Resolved tag that was installed (e.g. `v2.0.0-alpha.5`). |
| `binary-path` | Absolute path to the installed `dde` binary.             |

## Teardown

Composite GitHub Actions cannot register post-steps, so cleanup must be an
explicit workflow step:

```yaml
- if: always()
  working-directory: ./apps/web   # match the project-up working-directory
  run: dde project:down
```

For longer-lived runners (self-hosted) you may also want
`dde system:down` once all jobs in the matrix have finished.

## Supported runners

Same matrix as
[`setup-dde`](../setup-dde/README.md#supported-runners):
`ubuntu-latest`, `ubuntu-24.04-arm`, `macos-latest`, `macos-13`. Windows is
not supported.

## What runs under the hood

1. **`uses: setup-dde` with `system-install: 'true'`** — install + verify
   the binary, install `mkcert`, and run `dde system:install` as the
   runner user (dde escalates internally for steps that need root). See
   [`setup-dde`](../setup-dde/) for the underlying steps.
2. `cd $working-directory && dde project:up` — fails fast if
   `.dde/config.yml` is missing.
3. If `wait-url` is set: `curl -k` poll loop with 2s interval and 5s
   per-request timeout, until 2xx/3xx or `wait-timeout` expires. The
   `sleep 2` is a hard floor between attempts, so a slow first request
   plus the sleep yields ~25 attempts in 180s. The deadline check happens
   after each sleep, so wall-clock can overshoot `wait-timeout` by up to
   2 seconds before the action errors out.

The relative `uses: ./.github/actions/setup-dde` from inside this composite
action resolves against the action's own repository (not the caller's
workspace, which is how reusable workflows behave), so the same source
file works whether `project-up` is consumed cross-repo or from this repo's
self-test workflow.

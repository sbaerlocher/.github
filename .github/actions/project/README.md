# `sbaerlocher/.github/.github/actions/project`

Run a [whatwedo dde](https://github.com/whatwedo/dde) project lifecycle
command (`up`, `down`, `restart`, `update`, ...) on a GitHub Actions
runner. Installs the dde CLI on first use, optionally provisions the
host (Traefik, mkcert CA, dnsmasq) for `command: up`, executes
`dde project:<command>` in the project directory, and — for `up` —
optionally waits for an HTTP endpoint to respond before handing control
back to the workflow.

For setup-only (no project command) use the sibling
[`setup-dde`](../setup-dde/) action.

## Usage

Pick the most recent date tag from
<https://github.com/sbaerlocher/.github/tags> (used as `<TAG>` below).

### Bring the project up (default)

```yaml
- uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
- uses: sbaerlocher/.github/.github/actions/project@2026-04-30
- run: dde project:exec composer test:e2e
- if: always()
  uses: sbaerlocher/.github/.github/actions/project@2026-04-30
  with:
    command: down
```

### With a wait-for-ready URL

```yaml
- uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
- uses: sbaerlocher/.github/.github/actions/project@2026-04-30
  with:
    wait-url: https://myproject.test/healthz
    wait-timeout: '180'
- run: npm run test:e2e
- if: always()
  uses: sbaerlocher/.github/.github/actions/project@2026-04-30
  with:
    command: down
```

### Project lives in a subdirectory

```yaml
- uses: sbaerlocher/.github/.github/actions/project@2026-04-30
  with:
    working-directory: ./apps/web
```

### Other lifecycle commands

`command` accepts any `dde project:<X>` subcommand. `system-install` and
`wait-url` are only applied when `command: up`; for everything else they
are silently ignored, so callers can pass them unconditionally if a
matrix re-uses the same `with:` block.

```yaml
# Rebuild without re-provisioning the host
- uses: sbaerlocher/.github/.github/actions/project@2026-04-30
  with:
    command: update
```

## Inputs

| Input               | Default        | Description                                                              |
|---------------------|----------------|--------------------------------------------------------------------------|
| `command`           | `up`           | dde project subcommand (`up`, `down`, `restart`, `update`, ...).         |
| `version`           | `latest`       | dde version (`v2.0.0-alpha.5`, `2.0.0-alpha.5`, or `latest`).            |
| `working-directory` | `.`            | Directory with `.dde/config.yml`. Fails fast if missing.                 |
| `install-mkcert`    | `true`         | Install `mkcert` (+ `libnss3-tools` on Linux) for local TLS certs.       |
| `system-install`    | `true`         | Run `dde system:install` (host setup). Only applied when `command: up`.  |
| `wait-url`          | `""`           | Poll this URL until 2xx/3xx (TLS errors ignored). Only used for `up`.    |
| `wait-timeout`      | `180`          | Maximum seconds to wait for `wait-url`. Only applied when `command: up`. |
| `github-token`      | `github.token` | Token for the GitHub API call that resolves `latest`.                    |
| `repository`        | `whatwedo/dde` | Source repository. Override for forks or staging mirrors.                |

## Outputs

| Output        | Description                                              |
|---------------|----------------------------------------------------------|
| `version`     | Resolved tag that was installed (e.g. `v2.0.0-alpha.5`). |
| `binary-path` | Absolute path to the installed `dde` binary.             |

## Teardown

Composite GitHub Actions cannot register post-steps, so cleanup must be
an explicit workflow step. Re-using this action with `command: down` is
the simplest pattern:

```yaml
- if: always()
  uses: sbaerlocher/.github/.github/actions/project@2026-04-30
  with:
    command: down
    working-directory: ./apps/web   # match the up working-directory
```

For longer-lived runners (self-hosted) you may also want
`dde system:down` once all jobs in the matrix have finished.

## Supported runners

Same matrix as
[`setup-dde`](../setup-dde/README.md#supported-runners):
`ubuntu-latest`, `ubuntu-24.04-arm`, `macos-latest`, `macos-13`. Windows
is not supported.

## What runs under the hood

1. **`uses: setup-dde`** — install + verify the binary and install
   `mkcert`. `system-install` is forwarded to `setup-dde` only when
   `command: up`; for any other command it is forced to `'false'`, so
   the host is provisioned exactly once and not re-touched on
   `down`/`restart`/`update`/... See [`setup-dde`](../setup-dde/) for
   the underlying steps.
2. `cd $working-directory && dde project:$command` — fails fast if
   `working-directory` does not exist or contains no `.dde/config.yml`.
3. **For `command: up` only** — if `wait-url` is set: `curl -k` poll
   loop with 2s interval and 5s per-request timeout, until 2xx/3xx or
   `wait-timeout` expires. The `sleep 2` is a hard floor between
   attempts, so a slow first request plus the sleep yields ~25
   attempts in 180s. The deadline check happens after each sleep, so
   wall-clock can overshoot `wait-timeout` by up to 2 seconds before
   the action errors out.

`setup-dde` is referenced via the full repo path
(`sbaerlocher/.github/.github/actions/setup-dde@<DATE-TAG>`) because
`uses: ./...` from inside a composite action resolves against the
caller's `GITHUB_WORKSPACE`, not against the action's own repo (see
[actions/runner#2185](https://github.com/actions/runner/issues/2185)).
Renovate keeps that inner ref aligned with new date tags via the
standard github-actions manager.

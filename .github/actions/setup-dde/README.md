# `sbaerlocher/.github/.github/actions/setup-dde`

Install the [whatwedo `dde`](https://github.com/whatwedo/dde) CLI on a
GitHub Actions runner. Designed as a setup-style action — it puts the
binary on `PATH` and, optionally, installs host dependencies (`mkcert`)
and runs `dde system:install`.

## Usage

Pick the most recent date tag from
<https://github.com/sbaerlocher/.github/tags> (used as `<TAG>` below).

### Minimal — install the binary

```yaml
- uses: sbaerlocher/.github/.github/actions/setup-dde@2026-04-28
- run: dde --version
```

### Pin a specific dde version

```yaml
- uses: sbaerlocher/.github/.github/actions/setup-dde@2026-04-28
  with:
    version: v2.0.0-alpha.5
```

### Full setup for E2E tests

```yaml
- uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
- uses: sbaerlocher/.github/.github/actions/setup-dde@2026-04-28
  with:
    system-install: 'true'
- run: |
    dde project:up
    dde project:exec composer test:e2e
- if: always()
  run: dde project:down
```

For the higher-level "install + system:install + project:up" flow (or any
other `dde project:<command>`), use the sibling
[`project`](../project/) action instead.

## Inputs

| Input            | Default        | Description                                                              |
|------------------|----------------|--------------------------------------------------------------------------|
| `version`        | `latest`       | Tag to install (`v2.0.0-alpha.5`, `2.0.0-alpha.5`, or `latest`).         |
| `install-mkcert` | `true`         | Install `mkcert` (and `libnss3-tools` on Linux) for local TLS certs.     |
| `system-install` | `false`        | Run `dde system:install` (required for `dde project:up`).                |
| `github-token`   | `github.token` | Token for the GitHub API call that resolves `latest`.                    |
| `repository`     | `whatwedo/dde` | Source repository. Override for forks or staging mirrors.                |

`latest` resolves the most recent published release, including
pre-releases. The default `github-token` works for public repos and avoids
unauthenticated rate limits.

## Outputs

| Output        | Description                                              |
|---------------|----------------------------------------------------------|
| `version`     | Resolved tag that was installed (e.g. `v2.0.0-alpha.5`). |
| `binary-path` | Absolute path to the installed `dde` binary.             |

## Supported runners

| Runner             | Status                                                       |
|--------------------|--------------------------------------------------------------|
| `ubuntu-latest`    | Supported (`linux-amd64`).                                   |
| `ubuntu-24.04-arm` | Supported (`linux-arm64`).                                   |
| `macos-latest`     | Supported (`darwin-arm64`). `mkcert` installed via Homebrew. |
| `macos-13`         | Supported (`darwin-amd64`).                                  |
| `windows-*`        | Not supported — dde does not ship a Windows binary.          |

## Notes on `mkcert`

If `mkcert` is already on `PATH` (e.g. preinstalled on the runner image),
the action **skips** the apt/Homebrew install. On Linux, this means the
action does not separately ensure that `libnss3-tools` is present — the
package is only installed alongside `mkcert` via apt. On hosted GitHub
runners this never matters (the apt path always runs because `mkcert` is
not preinstalled), but on self-hosted Linux runners with a non-apt mkcert
build, `mkcert -install` (called by `dde system:install`) may silently
fail to update the system NSS database. If that applies, install
`libnss3-tools` in your runner image.

## Notes for `system-install: true`

`dde system:install` performs host-level configuration (writes
`/etc/systemd/resolved.conf.d/dde-test.conf` on Linux, restarts
`systemd-resolved`) and starts the global Traefik, dnsmasq and SSH-Agent
containers. The action invokes it as the runner user — dde escalates
internally (passwordless sudo, which GitHub-hosted runners provide) for
the individual steps that need root. Wrapping the whole call in `sudo`
would leave dde's state files (`~/.dde/data/...`) root-owned and break
the subsequent unprivileged `dde project:*` calls.

`DDE_CONFIG_DIR` / `DDE_DATA_DIR` propagate naturally, so the caller
can isolate dde state into a temp directory:

```yaml
- uses: sbaerlocher/.github/.github/actions/setup-dde@2026-04-28
  with:
    system-install: 'true'
  env:
    DDE_CONFIG_DIR: ${{ runner.temp }}/dde-config
    DDE_DATA_DIR:   ${{ runner.temp }}/dde-data
```

## Security

Each dde release ships a `checksums.txt` SHA256 manifest alongside the
binaries. The action downloads it from the same release and verifies the
binary against it before placing it on `PATH`. Verification is fail-closed:
a missing asset, a missing checksum file, or a hash mismatch aborts the
step.

Note that `checksums.txt` is fetched over HTTPS from the same GitHub
release as the binary; it is not signed. Trust is anchored on
`whatwedo/dde`'s release pipeline. If you need a stronger trust root, pin
`version` to an exact tag rather than `latest` and audit it out-of-band.

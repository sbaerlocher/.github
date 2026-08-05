# Reusable GitHub Actions Workflows

Centralized CI/CD building blocks for all repositories under
[`sbaerlocher`](https://github.com/sbaerlocher). Consumer repositories pin
each workflow by date tag and let Renovate keep them current.

- **Model:** rolling release with date tags (`YYYY-MM-DD`)
- **Reusable workflows:** 24 (plus 4 internal to this repo)
- **Last updated:** 2026-07-18

See [AGENTS.md](./AGENTS.md) for AI-agent context.

---

## Quick Start

Pick the most recent date tag from
<https://github.com/sbaerlocher/.github/tags> (used as `<TAG>` below) and
reference workflows from your consumer repository.

### JavaScript / TypeScript

```yaml
# .github/workflows/ci.yml
name: Continuous Integration
on:
  pull_request:
    branches: [main]
  workflow_call:

jobs:
  ci:
    uses: sbaerlocher/.github/.github/workflows/ci-js.yml@<TAG>
    with:
      package-manager: pnpm
      enable-security-scans: true
    secrets:
      CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}
```

### Go

```yaml
jobs:
  ci:
    uses: sbaerlocher/.github/.github/workflows/ci-go.yml@<TAG>
    with:
      go-version: '1.25'
```

### Terraform

```yaml
# .github/workflows/ci.yml
jobs:
  terraform:
    uses: sbaerlocher/.github/.github/workflows/ci-terraform.yml@<TAG>

# .github/workflows/deploy.yml — on push to main
jobs:
  deploy:
    uses: sbaerlocher/.github/.github/workflows/deploy-terraform.yml@<TAG>
    with:
      environment: production
      bw-secrets: |
        <uuid> > ENV_VAR
    secrets:
      BW_ACCESS_TOKEN: ${{ secrets.BW_ACCESS_TOKEN }}
```

---

## Workflow Catalogue

All files live in [.github/workflows/](./.github/workflows/).

### CI — Continuous Integration (5)

| File                                                       | Purpose                                  |
| ---------------------------------------------------------- | ---------------------------------------- |
| [`ci-ansible.yml`](./.github/workflows/ci-ansible.yml)     | Ansible syntax & ansible-lint            |
| [`ci-gitops.yml`](./.github/workflows/ci-gitops.yml)       | Fleet, Helm, kubeconform, pytest         |
| [`ci-go.yml`](./.github/workflows/ci-go.yml)               | Build, test, golangci-lint, gosec        |
| [`ci-js.yml`](./.github/workflows/ci-js.yml)               | Quality, tests, audit (multi-pm)         |
| [`ci-terraform.yml`](./.github/workflows/ci-terraform.yml) | `terraform fmt`, validate, tflint, Trivy |

### Security — Scanning & Analysis (6)

| File                                                                     | Tools                              |
| ------------------------------------------------------------------------ | ---------------------------------- |
| [`security-code.yml`](./.github/workflows/security-code.yml)             | CodeQL (multi-language SAST)       |
| [`security-config.yml`](./.github/workflows/security-config.yml)         | Checkov, kubeconform, kubesec      |
| [`security-containers.yml`](./.github/workflows/security-containers.yml) | Trivy + Grype                      |
| [`security-deps.yml`](./.github/workflows/security-deps.yml)             | govulncheck, npm audit, safety     |
| [`security-sbom.yml`](./.github/workflows/security-sbom.yml)             | CycloneDX SBOM generation          |
| [`security-secrets.yml`](./.github/workflows/security-secrets.yml)       | Gitleaks, TruffleHog, key patterns |

### Deploy (2)

- [`deploy-cloudflare-workers.yml`](./.github/workflows/deploy-cloudflare-workers.yml)
  — Cloudflare Workers via Wrangler
- [`deploy-terraform.yml`](./.github/workflows/deploy-terraform.yml)
  — Terraform plan & apply with Bitwarden secret injection. In drift mode also
  emits a value-free `drift_summary` output (drifting resource addresses +
  actions, never attribute values) for `ops-drift-issue.yml`.

### Release (4)

| File                                                           | Output                               |
| -------------------------------------------------------------- | ------------------------------------ |
| [`release-docker.yml`](./.github/workflows/release-docker.yml) | Multi-arch Docker images to GHCR     |
| [`release-go.yml`](./.github/workflows/release-go.yml)         | GoReleaser binaries + GitHub Release |
| [`release-helm.yml`](./.github/workflows/release-helm.yml)     | Helm OCI chart publish               |
| [`release-npm.yml`](./.github/workflows/release-npm.yml)       | NPM publish with provenance + SBOM   |

### Operations (3)

- [`ops-terraform-orchestration.yml`](./.github/workflows/ops-terraform-orchestration.yml)
  — Multi-environment Terraform deployment driver
- [`ops-terraform-report.yml`](./.github/workflows/ops-terraform-report.yml)
  — Render Terraform pipeline report (Step Summary, metadata artifact, notification)
- [`ops-drift-issue.yml`](./.github/workflows/ops-drift-issue.yml)
  — Upsert a GitHub issue when Terraform drift is detected. With the optional
  `drift-summary` input it maintains a marker-delimited summary block of the
  drifting resource addresses in the issue body and comments only when that set
  changes (no summary → unchanged: comment on every run).

### AI — Private Repos Only (2)

- [`ai-claude.yml`](./.github/workflows/ai-claude.yml)
  — On-demand `@claude` mentions in issues and PRs
- [`ai-claude-review.yml`](./.github/workflows/ai-claude-review.yml)
  — Automatic code review on PRs (uses REVIEW.md as context)

### E2E (2)

| File                                                   | Purpose                                          |
| ------------------------------------------------------ | ------------------------------------------------ |
| [`e2e-docker.yml`](./.github/workflows/e2e-docker.yml) | End-to-end tests via Docker Compose + Playwright |
| [`e2e-dde.yml`](./.github/workflows/e2e-dde.yml)       | End-to-end tests via whatwedo dde + Playwright   |

---

## Composite Actions

In addition to reusable workflows, this repo ships composite actions under
[.github/actions/](./.github/actions/) for use from any consumer workflow.

| Action                                                                                | Purpose                                                                  |
| ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| [`setup-dde`](./.github/actions/setup-dde/)                                           | Install the [whatwedo dde](https://github.com/whatwedo/dde) CLI          |
| [`project`](./.github/actions/project/)                                               | Install dde + run any `dde project:<command>` (default `up`) for E2E     |
| [`sbom-npm`](./.github/actions/sbom-npm/)                                             | CycloneDX SBOM for npm/pnpm/yarn/bun projects (internal)                 |
| [`validate-observability-configs`](./.github/actions/validate-observability-configs/) | Validate Grafana Alloy and JSON configs in observability Terraform repos |

For a complete Playwright + dde E2E job, use the
[`e2e-dde.yml`](./.github/workflows/e2e-dde.yml) reusable workflow — it
wires `project` together with Node, browser install, artifacts, and PR
commenting. Reach for the composite actions directly only when you need
a custom test surface that the workflow doesn't cover.

Reference an action from a consumer repository (Renovate keeps the date
tag up to date):

```yaml
- uses: sbaerlocher/.github/.github/actions/project@2026-04-30
  with:
    wait-url: https://myproject.test/healthz

- if: always()
  uses: sbaerlocher/.github/.github/actions/project@2026-04-30
  with:
    command: down
```

---

## Project Type Guide

**Per language / stack:**

- **JavaScript / TypeScript** — `ci-js.yml`; optional `release-npm.yml`,
  `deploy-cloudflare-workers.yml`
- **Go** — `ci-go.yml`; optional `release-go.yml`, `release-docker.yml`
- **Terraform / IaC** — `ci-terraform.yml`, `deploy-terraform.yml`;
  optional `ops-terraform-orchestration.yml`
- **GitOps (Fleet / Helm)** — `ci-gitops.yml`; optional `release-helm.yml`
- **Serverless (CF Workers)** — `ci-js.yml`, `deploy-cloudflare-workers.yml`

**Cross-cutting:**

- **Public repos (any language)** — add `security-code.yml` (CodeQL).
  Weekly `security-*` scans recommended.
- **Private repos (any language)** — add `ai-claude-review.yml` and
  `ai-claude.yml`.

Weekly security scans should be scheduled at `0 6 * * 1` (Monday 06:00 UTC).
Never wire scheduled workflows as required status checks — they don't run on
PRs and would block every merge.

---

## Versioning

Reference workflows from a consumer repo by **date tag**:

```yaml
uses: sbaerlocher/.github/.github/workflows/ci-js.yml@2026-04-25
```

Rules:

- Date tag is mandatory in consumer repos. `@main` and `@v1` are not
  supported.
- Every push to `main` moves that UTC day's tag to the newest commit, so one
  tag covers the whole day. A tag stops changing once its day is over; only
  the current day's tag is still mutable. Pin a past day's tag if you need a
  fixed target. See [CHANGELOG.md](./CHANGELOG.md) for the history.
- Renovate updates these tags automatically via the custom manager in
  [`renovate-base.json`](./renovate-base.json).

---

## Required Secrets in Consumer Repos

| Secret                    | Purpose                   | Required for                   |
| ------------------------- | ------------------------- | ------------------------------ |
| `BW_ACCESS_TOKEN`         | Bitwarden Secrets Manager | `deploy-terraform`, CF Workers |
| `CODECOV_TOKEN`           | Code coverage upload      | `ci-js`, `ci-go` (optional)    |
| `NPM_TOKEN`               | NPM publish               | `release-npm`                  |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude AI workflows       | private repos only             |

---

## Troubleshooting

### Workflow not found

```text
Error: Unable to resolve action sbaerlocher/.github/.github/workflows/ci-js.yml@<TAG>
```

Check the nested path: it's `sbaerlocher/.github` (the repo) followed by
`/.github/workflows/<file>` (the path inside the repo). Both `.github`
segments are required.

### Cache misses

Ensure your lockfile is committed (`pnpm-lock.yaml`, `package-lock.json`,
`yarn.lock`, `bun.lockb`, or `go.sum`).

### Security scans too slow on PRs

Disable scheduled-only scans on `pull_request`:

```yaml
with:
  enable-security-scans: ${{ github.ref == 'refs/heads/main' }}
```

### SARIF upload fails on private repo

`security-code.yml` and friends only upload SARIF when
`enable-sarif-upload: true` _and_ the repo is public (or has GitHub
Advanced Security). Private repos without GHAS should leave the input at
its default `false` and rely on artifact uploads instead.

---

## Working on This Repository

Local tasks run through [`just`](https://just.systems), the org-wide command
runner. Run it without arguments to list the recipes:

| Recipe            | What it does                                              |
| ----------------- | --------------------------------------------------------- |
| `just`            | List all recipes                                          |
| `just lint`       | yamllint, Renovate JSON validity, actionlint, `fmt-check` |
| `just actionlint` | actionlint alone — local binary or container, by coverage |
| `just test`       | Script self-checks under `scripts/tests/`                 |
| `just fmt`        | prettier over Markdown and JSON                           |
| `just fmt-check`  | prettier `--check` — the formatting gate inside `lint`    |

There is no `build` or `dev` recipe — this repository ships no build artifact
and has no dev loop. `templates/justfile` is the reference template consumer
repositories copy, and carries the full standard verb set.

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the full contribution workflow.

---

## Related Documentation

- [REVIEW.md](./REVIEW.md) — code review guidelines for this repo
- [CHANGELOG.md](./CHANGELOG.md) — release history
- [AGENTS.md](./AGENTS.md) — AI agent context
- [SECURITY.md](./SECURITY.md) — vulnerability reporting

---

## License

[MIT](./LICENSE) — Simon Bärlocher.

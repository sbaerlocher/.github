# Reusable GitHub Actions Workflows

**Repository Type**: Centralized Workflow Repository
**Purpose**: Provide reusable GitHub Actions workflows for all sbaerlocher projects
**Visibility**: Public
**Last Updated**: 2026-07-18

---

## Context for AI Agents

This repository contains centralized, reusable GitHub Actions workflows used across all
repositories in the sbaerlocher organization. When working on this repository, you are
directly impacting the CI/CD pipelines of multiple projects.

### What This Repository Does

**Centralized Workflow Management**:

- Provides reusable workflows for CI, Security, Deployment, and Release operations
- Eliminates workflow duplication across 10+ repositories
- Ensures consistent CI/CD behavior across all projects
- Simplifies workflow maintenance (fix once, benefits all repos)

**Current Statistics**:

- **Total Workflows**: 28 files in [.github/workflows/](./.github/workflows/) — 24 reusable
  (`workflow_call`) plus 4 internal workflows that run only in this repo
  (`merge.yml`, `pull-request.yml`, `test-actions-dde.yml`, `weekly-security.yml`)
- **Reusable Categories**: CI (5), Security (6), Deploy (2), Release (4), Operations (3),
  AI (2), E2E (2)
- **Consumers**: applications, infrastructure, authentication, observability, functions,
  sbaerlocher.ch, tsmetrics, and more

---

## Important Standards & Conventions

### Workflow Layering

Consumer repositories follow a strict three-layer split:

1. **Repo workflow** contains only `on:`, `permissions:`, and `uses:` —
   never a multi-line `run:` step. It is a thin trigger hull.
2. **Reusable workflow** in `sbaerlocher/.github` owns the pipeline logic
   (job sequences, tool calls, reporting, notification) and exposes it via
   `inputs:` / `outputs:` / `secrets:`.
3. **Composite action** in `.github/actions/` owns single tool-bootstrap
   steps when the same shell logic appears in more than one reusable.

**Concurrency is owned by the reusable**, never by both the repo workflow
and the reusable for the same logical group. If a reusable declares its
own `concurrency:` block, the calling repo workflow must not set one for
the same scope. Where a reusable supports it (e.g. `deploy-terraform.yml`
via `cancel-in-progress` + `concurrency-suffix` inputs), the caller picks
the cancellation policy and group suffix per call.

This rule eliminates the "two limiters in series" pattern that previously
caused queue pile-ups and surprise cancellations when consumer repos
wrapped a reusable with their own `concurrency:` block.

### Workflow Naming Convention

**File Names** (kebab-case):

- `ci-*.yml` - Continuous Integration workflows
- `security-*.yml` - Security scanning workflows
- `deploy-*.yml` - Deployment workflows
- `release-*.yml` - Release workflows
- `ops-*.yml` - Operational workflows
- `ai-*.yml` - AI-assisted workflows
- `e2e-*.yml` - End-to-end test workflows
- `test-*.yml` - **Internal self-test workflows for actions in this repo
  (NOT reusable — `paths:` filtered to a specific action's source files)**

**Workflow Names** (`name:` field):

- Always use full names (no abbreviations)
- Example: `name: Continuous Integration` (NOT `CI`)
- Example: `name: Security Scanning` (NOT `Security`)

### Action Security - SHA Pinning

**CRITICAL SECURITY REQUIREMENT**:

All GitHub Actions MUST be pinned to full commit SHA with version comment:

```yaml
# ✅ CORRECT - SHA pinned with version comment
uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4.1.1
uses: actions/setup-node@60edb5dd545a775178f52524783378180af0d1f8 # v4.0.2

# ❌ WRONG - Tag only (mutable, security risk)
uses: actions/checkout@v4
uses: actions/setup-node@v4.0.2
```

**Why SHA Pinning?**

- **Immutable**: SHA cannot be changed after commit
- **Supply-chain security**: Protects against tag hijacking attacks
- **Audit trail**: Exact version is always traceable
- **GitHub recommendation**: For security-critical workflows

**Renovate handles updates**: SHA references are automatically updated with new version comments.

### Workflow Versioning

This repository uses a **rolling release** model with date-based tags
(`YYYY-MM-DD`). There are no `v1`/`v2` semver tags.

```yaml
# Consumer repository — pin to a specific release date
uses: sbaerlocher/.github/.github/workflows/ci-js.yml@2026-04-25
```

**Rules**:

- Consumers MUST reference workflows by date tag.
- `@main` is forbidden in consumer repos — breaking changes would propagate
  immediately to all of them.
- `merge.yml` tags every push to `main` with the current UTC date, moving that
  day's tag to the newest commit. A tag therefore covers the whole day and
  stops changing once the day is over; only the current day's tag is mutable.
- Renovate updates date tags in consumer repos automatically via the
  custom manager defined in `renovate-base.json`.

### Runner Convention

Every reusable workflow exposes a `runner` input, and every `runs-on:` in it
resolves through that input rather than naming a runner directly:

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

```yaml
runs-on: ${{ inputs.runner }}
```

`runs-on` sits in the called workflow and a caller cannot override it, so
without this input no consumer can reach a self-hosted runner. The default
keeps every existing caller on `ubuntu-latest`; a consumer opts in per repo
with `with: runner: <label>`.

**Single label only.** The input is a `type: string` interpolated bare, so it
resolves as one label. The sequence form (`[self-hosted, linux, x64]`) and the
mapping form (`group:`) need the expression to evaluate to a non-string via
`fromJSON()`, which this shape does not do — a caller passing a runner-group
name gets it matched as a label no runner carries, and the job waits for a
runner until it times out rather than failing. Say so in the description
instead of implying broader support.

**Carry platform constraints into the description.** A hardcoded
`ubuntu-latest` used to enforce a platform requirement structurally; the input
removes that enforcement, so a workflow that only works on Linux states it in
its own `runner` description — `e2e-dde.yml` (needs Docker) and
`security-secrets.yml` (TruffleHog shells out to `apt-get` and a Docker image)
both do.

**Scope.** Only workflows with a `workflow_call` trigger. The internal
workflows have no caller that could set an input, so they keep naming their
runner directly.

`runner` is workflow-wide: a consumer cannot route individual jobs of a
multi-job reusable to different runners. Add a second input if that need is
ever demonstrated.

### Concurrency Convention

Every reusable workflow exposes the same two inputs so consumers can adjust
concurrency without forking the workflow:

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

The concurrency block always renders as:

```yaml
concurrency:
  group: >-
    <base-group>${{
      inputs.concurrency-suffix != '' && format('-{0}', inputs.concurrency-suffix) || ''
    }}
  cancel-in-progress: ${{ inputs.cancel-in-progress }}
```

**Defaults — and when to override:**

- **CI / Security / E2E**: default `cancel-in-progress: true`. The latest push
  supersedes the previous run. Override to `false` for matrix legs that must
  all complete (e.g. compliance reports).
- **Deploy / Release / Ops**: default `cancel-in-progress: false`. A
  half-applied deploy or half-uploaded artifact is worse than waiting.
  Override to `true` for drift / scan use-cases where the latest invocation
  should supersede the previous (this is exactly why `deploy-terraform.yml`
  takes both inputs — drift mode wants `true`, deploy mode wants `false`).
- **Suffix**: empty by default. Set when the same caller workflow invokes
  the same reusable from multiple matrix legs or modes that must run
  in parallel rather than serialise. Example: `concurrency-suffix: drift`
  on a drift-detection job that calls `deploy-terraform.yml` alongside
  the deploy job.

**Two base-group patterns are in use:**

- **Caller-isolated** — `${{ github.workflow }}-${{ github.ref }}`. Used by
  CI, Security, Release, E2E, and most Ops/Deploy workflows. `github.workflow`
  resolves to the _caller's_ workflow name when invoked via `workflow_call`,
  so different callers automatically get different groups.
- **Resource-locked** — built from inputs (e.g.
  `${{ inputs.project-name }}-terraform-${{ inputs.environment }}` in
  `deploy-terraform.yml`, or `${{ inputs.project-name }}-${{ inputs.environment }}`
  in `ops-drift-issue.yml`). Used when the workflow guards a shared resource
  (Terraform state, GitHub-issue list) that must serialise across _all_
  callers, not just the same caller.

When adding a new reusable workflow, pick the base-group pattern based on
whether it serialises a shared resource, and always expose both inputs so
consumers have an escape hatch.

---

## Workflow Categories

### CI - Continuous Integration (5)

**Purpose**: Validate code quality, tests, and security before merge

| Workflow       | File               | Description               | Languages/Tools                  |
| -------------- | ------------------ | ------------------------- | -------------------------------- |
| CI (Ansible)   | `ci-ansible.yml`   | Ansible syntax & lint     | Ansible, ansible-lint            |
| CI (GitOps)    | `ci-gitops.yml`    | Fleet & K8s validation    | Fleet, Helm, kubeconform, pytest |
| CI (Go)        | `ci-go.yml`        | Go build, test & security | Go, golangci-lint, gosec         |
| CI (JS/TS)     | `ci-js.yml`        | Quality, tests & security | JS/TS, Prettier, ESLint, Vitest  |
| CI (Terraform) | `ci-terraform.yml` | Terraform validation      | Terraform, tflint                |

**Key Features**:

- Parallel execution (quality + tests)
- Smart caching (dependencies, build artifacts)
- Conditional security scans
- Typical runtime: 5-12 minutes

### Security - Scanning & Analysis (6)

**Purpose**: Comprehensive security scanning (SAST, secrets, dependencies, containers)

| Workflow        | File                      | Description                | Tools                              |
| --------------- | ------------------------- | -------------------------- | ---------------------------------- |
| SAST            | `security-code.yml`       | Static code analysis       | CodeQL (multi-language)            |
| Config Security | `security-config.yml`     | IaC security               | Checkov, Kubeconform               |
| Dependencies    | `security-deps.yml`       | Dependency vulnerabilities | govulncheck, npm audit             |
| Secrets         | `security-secrets.yml`    | Secret detection           | Gitleaks, TruffleHog, key patterns |
| Containers      | `security-containers.yml` | Container scanning         | Trivy, Grype                       |
| Supply Chain    | `security-sbom.yml`       | SBOM & signing             | Cosign, CycloneDX                  |

**Strategy**:

- **PR**: CodeQL only (fast feedback)
- **Weekly**: Deep scans (scheduled Monday 06:00 UTC)
- **Public Repos**: SARIF upload to GitHub Security tab (free)
- **Private Repos**: Artifact upload (JSON/Table format)

### Deploy - Deployment Operations (2)

**Purpose**: Deploy infrastructure and applications

| Workflow           | File                            | Description            | Use Case             |
| ------------------ | ------------------------------- | ---------------------- | -------------------- |
| Terraform Deploy   | `deploy-terraform.yml`          | Terraform plan & apply | IaC deployments      |
| Cloudflare Workers | `deploy-cloudflare-workers.yml` | Wrangler deploy        | Serverless functions |

**Features**:

- Bitwarden Secrets Manager integration
- Environment-based deployments
- Approval gates for production

### Release - Release Management (4)

**Purpose**: Build and publish versioned artifacts

| Workflow       | File                 | Description         | Output                    |
| -------------- | -------------------- | ------------------- | ------------------------- |
| Go Release     | `release-go.yml`     | GoReleaser          | Binaries (multi-platform) |
| Docker Release | `release-docker.yml` | Docker build & push | Container images          |
| Helm Release   | `release-helm.yml`   | Helm chart publish  | OCI charts                |
| NPM Release    | `release-npm.yml`    | NPM publish         | Package with provenance   |

**Trigger**: `push` events on tags (`v*`)

### Operations - Operational Tasks (3)

**Purpose**: Scheduled maintenance and operational tasks

| Workflow         | File                              | Description                              | Schedule  |
| ---------------- | --------------------------------- | ---------------------------------------- | --------- |
| Orchestration    | `ops-terraform-orchestration.yml` | Multi-environment TF                     | On-demand |
| Terraform Report | `ops-terraform-report.yml`        | Pipeline report + metadata artifact      | On-demand |
| Drift Issue      | `ops-drift-issue.yml`             | Upsert drift issue (idempotent by title) | On-demand |

`ops-terraform-report.yml` consumes outputs from
`ops-terraform-orchestration.yml` + `deploy-terraform.yml` and renders the
deploy/drift summary that consumer repos used to inline. `ops-drift-issue.yml`
replaces the inline `gh issue create/comment` block in consumer drift
workflows; it serialises by `project + environment` so two scheduled drift
runs cannot race on `gh issue list`.

### AI - AI-Assisted Workflows (2)

**Purpose**: AI-powered code review and on-demand assistance (private repos only)

| Workflow    | File                   | Description                        |
| ----------- | ---------------------- | ---------------------------------- |
| Code Review | `ai-claude-review.yml` | Auto code review (reads REVIEW.md) |
| On-demand   | `ai-claude.yml`        | On-demand @claude mentions         |

### E2E - End-to-End Tests (2)

**Purpose**: End-to-end testing with Docker Compose or whatwedo dde

| Workflow   | File             | Description                                                  |
| ---------- | ---------------- | ------------------------------------------------------------ |
| E2E Docker | `e2e-docker.yml` | E2E tests via Docker Compose + Playwright                    |
| E2E dde    | `e2e-dde.yml`    | E2E tests via whatwedo `dde project:up` + Playwright (Linux) |

`e2e-dde.yml` is the dde-native counterpart to `e2e-docker.yml`. Inputs
overlap (Playwright/Node setup is identical); the stack-management surface
swaps `compose-file` / `compose-profile` for `project-directory` /
`wait-url`. Linux-only (`dde system:install` requires Docker, which hosted
macOS runners don't ship).

### Internal Workflows (4)

**Purpose**: This repository's own CI and release plumbing. None of these
carry a `workflow_call` trigger — they are not reusable from consumer repos.

| Workflow         | File                   | Description                                |
| ---------------- | ---------------------- | ------------------------------------------ |
| Test dde actions | `test-actions-dde.yml` | Smoke-test `setup-dde` on Linux/macOS      |
| Pull Request     | `pull-request.yml`     | `just lint` + `just test` on PRs to `main` |
| Merge to Main    | `merge.yml`            | Moves the `YYYY-MM-DD` date tag on push    |
| Weekly Security  | `weekly-security.yml`  | Scheduled config + secret self-scan (Mon)  |

---

## Composite Actions

Located under [`.github/actions/`](./.github/actions/). Consume from any
workflow via `sbaerlocher/.github/.github/actions/<name>@<DATE-TAG>`.

| Action                           | File                                              | Purpose                                                      |
| -------------------------------- | ------------------------------------------------- | ------------------------------------------------------------ |
| `setup-dde`                      | `.github/actions/setup-dde/`                      | Install whatwedo dde CLI; optional mkcert + `system:install` |
| `project`                        | `.github/actions/project/`                        | Install dde + run any `dde project:<command>` (default `up`) |
| `sbom-npm`                       | `.github/actions/sbom-npm/`                       | CycloneDX SBOM for npm/pnpm/yarn/bun (internal helper)       |
| `validate-observability-configs` | `.github/actions/validate-observability-configs/` | Validate Grafana Alloy and JSON observability configs        |

### dde actions (`setup-dde`, `project`)

`setup-dde` downloads the dde binary from
[`whatwedo/dde`](https://github.com/whatwedo/dde) GitHub releases, verifies
SHA256 against `checksums.txt`, places it on `PATH`, and optionally installs
`mkcert` and runs `dde system:install` as the runner user. dde escalates
internally (passwordless sudo, which GitHub-hosted runners provide) for the
individual steps that need root — wrapping the whole call in `sudo` would
leave the state files in `~/.dde/data/` root-owned and break the subsequent
unprivileged `dde project:*` calls.

`project` is a thin wrapper around `setup-dde` plus a single
`dde project:<command>` invocation. The `command` input (default `up`)
selects the lifecycle step; `system-install` and `wait-url` are only
applied when `command: up` and silently ignored otherwise, so callers
can pass them unconditionally. Both reusable workflows (`e2e-dde.yml`)
and composite actions (`project`) must reference sibling actions via
the full versioned path
(`sbaerlocher/.github/.github/actions/<name>@<DATE-TAG>`), because
`uses: ./...` always resolves against the caller's `GITHUB_WORKSPACE`,
never against the action/workflow's own repo
(see [actions/runner#2185](https://github.com/actions/runner/issues/2185)).
Renovate keeps the inner ref in `project/action.yml` aligned with new
date tags via the standard github-actions manager.

The self-test workflow (`test-actions-dde.yml`) is the one place `./...`
is safe — it's a normal workflow that runs `actions/checkout` first, so
the workspace coincidentally matches the action's repo. Side-effect of
the full-path pin: the `smoke-project-*` jobs exercise the _tagged_
`setup-dde`, not the in-PR copy, so changes to `setup-dde/action.yml`
are only validated end-to-end through `project` once a new date tag
has been cut. Direct changes to `setup-dde` are still covered by the
`smoke-setup-dde` matrix in the same workflow.

Composite actions have no `post:` hook, so cleanup is always an explicit
`if: always()` step in the consumer workflow — typically a re-use of
`project` with `command: down`, or a plain `run: dde project:down`.

### sbom-npm

Generates a CycloneDX SBOM for JavaScript/TypeScript projects. Consumed by
`release-npm.yml` and `security-sbom.yml`; not intended as a standalone
public action.

---

## Workflow Development Guidelines

### Adding a New Workflow

1. **Naming**: Follow kebab-case convention (`category-purpose.yml`)
2. **Documentation**: Add comprehensive description in file header
3. **Security**: Pin all actions to SHA with version comment
4. **Testing**: Test in a consumer repository before merging
5. **README**: Update [README.md](./README.md) with new workflow details
6. **CHANGELOG**: Document changes in [CHANGELOG.md](./CHANGELOG.md)

### Modifying Existing Workflows

**CRITICAL**: Changes to reusable workflows affect ALL consumer repositories!

**Process**:

1. **Test First**: Create a test version (e.g., `ci-js-test.yml`)
2. **Consumer Testing**: Test in 1-2 consumer repos pointing at `@main`
3. **Breaking Changes**: Cut a new dated tag and add a `### ⚠ BREAKING`
   heading to that tag's `CHANGELOG.md` entry, naming the affected workflow
   and a one-line migration step. This is the single channel consumers scan
   before bumping — see the "Breaking changes & support policy" section at
   the top of `CHANGELOG.md`.
4. **Non-Breaking**: A regular dated tag is sufficient
5. **Document**: Update CHANGELOG.md with all changes

**Breaking Changes Include**:

- Changing required inputs
- Removing inputs/outputs
- Changing default behavior
- Removing features

### Workflow Inputs & Secrets

**Best Practices**:

```yaml
on:
  workflow_call:
    inputs:
      # Use descriptive names
      terraform-version:
        description: 'Terraform version to use'
        type: string
        required: false
        default: '1.14.3'

      # Boolean inputs for feature flags
      enable-security-scans:
        description: 'Enable security scanning'
        type: boolean
        required: false
        default: false

    secrets:
      # Document required secrets
      BW_ACCESS_TOKEN:
        description: 'Bitwarden Access Token for secret retrieval'
        required: false
```

**Guidelines**:

- Provide sensible defaults
- Make inputs optional when possible
- Use boolean flags for conditional features
- Document all inputs/secrets clearly

### Error Handling

**Workflow Resilience**:

```yaml
# Continue on error for non-critical steps
- name: Optional security scan
  continue-on-error: true
  run: |
    trivy scan .

# Explicit failure for critical steps
- name: Required validation
  run: |
    terraform validate || exit 1
```

**Conditional Execution**:

```yaml
# Skip steps based on conditions
- name: Deploy to production
  if: github.ref == 'refs/heads/main'
  run: |
    ./deploy.sh
```

---

## Consumer Repository Integration

### Usage Pattern

**In consumer repository** (e.g., `sbaerlocher/functions`):

```yaml
# .github/workflows/ci.yml
name: Continuous Integration

on:
  pull_request:
    branches: [main]
  workflow_call:

jobs:
  ci:
    uses: sbaerlocher/.github/.github/workflows/ci-js.yml@2026-04-25
    with:
      package-manager: pnpm
      enable-security-scans: true
      enable-dependency-review: true
    secrets:
      CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}
```

### Required Secrets in Consumer Repos

**Common Secrets**:

| Secret                    | Purpose                   | Required For             |
| ------------------------- | ------------------------- | ------------------------ |
| `BW_ACCESS_TOKEN`         | Bitwarden Secrets Manager | Terraform/Workers deploy |
| `CODECOV_TOKEN`           | Code coverage upload      | CI workflows             |
| `CLAUDE_CODE_OAUTH_TOKEN` | AI code review            | Private repos only       |

---

## Troubleshooting

### Workflow Not Found Error

```text
Error: Unable to resolve action sbaerlocher/.github/.github/workflows/ci-js.yml@main
```

**Solution**: Check the nested path structure

```yaml
uses: sbaerlocher/.github/.github/workflows/ci-js.yml@2026-04-25
#     ^^^^^^^^^^^ Repo      ^^^^^^^^^^^^^^^^ Nested .github directory
```

### Security Scans Too Slow

Disable security scans in PRs, run only on main:

```yaml
with:
  enable-security-scans: ${{ github.ref == 'refs/heads/main' }}
```

### Cache Misses

Ensure lock files are committed:

- `pnpm-lock.yaml`
- `package-lock.json`
- `yarn.lock`
- `go.sum`

### SHA Pinning Not Working

**Problem**: Renovate not updating SHA references

**Solution**: Ensure `renovate-base.json` includes:

```json
{
  "github-actions": {
    "pinDigests": true
  }
}
```

---

## Repository Structure

```text
.github/
├── .github/
│   ├── workflows/           # 28 files: 24 reusable + 4 internal
│   │   ├── ai-*.yml        # AI workflows
│   │   ├── ci-*.yml        # CI workflows
│   │   ├── deploy-*.yml    # Deploy workflows
│   │   ├── e2e-*.yml       # End-to-end test workflows
│   │   ├── ops-*.yml       # Operations workflows
│   │   ├── release-*.yml   # Release workflows
│   │   ├── security-*.yml  # Security workflows
│   │   ├── test-*.yml      # Internal self-tests (NOT reusable)
│   │   ├── merge.yml       # Internal: moves the date tag on push to main
│   │   ├── pull-request.yml # Internal: lint + test on this repo's PRs
│   │   └── weekly-security.yml # Internal: scheduled self-scan
│   ├── ISSUE_TEMPLATE/     # Org-default issue forms
│   ├── CODEOWNERS          # Repository owners
│   └── pull_request_template.md
├── AGENTS.md               # AI agent documentation (this file)
├── CLAUDE.md               # Claude Code import
├── README.md               # Human-readable documentation
├── CHANGELOG.md            # Version history
├── SECURITY.md             # Org-default security policy
├── REVIEW.md               # Code review guidelines for this repo
├── LICENSE                 # MIT License
├── .editorconfig           # Editor consistency
├── .prettierrc             # Prettier configuration
├── .gitignore              # Git ignore patterns
├── renovate-*.json         # Shared Renovate presets
└── renovate.json           # Main Renovate config
```

---

## Important Notes for AI Agents

### What You Should Do

✅ **When Adding Workflows**:

- Follow naming conventions strictly
- Pin all actions to SHA with version comment
- Test in consumer repos before merging
- Update README.md and CHANGELOG.md
- Consider backward compatibility

✅ **When Modifying Workflows**:

- Test changes thoroughly
- Consider impact on all consumer repos
- Use versioning for breaking changes
- Document all changes

✅ **Security Best Practices**:

- Always use SHA pinning for actions
- Validate all inputs
- Use secrets properly (never log them)
- Follow least-privilege principle

### What You Should NOT Do

❌ **Breaking Changes Without a New Date Tag**:

- NEVER ship a breaking change without cutting a new dated release tag and
  noting the break in `CHANGELOG.md`
- NEVER remove inputs/outputs without a deprecation notice
- NEVER change default behavior without testing impact in a consumer repo

❌ **Security Anti-Patterns**:

- NEVER use tag-only action references (`@v4`) for third-party actions
- NEVER log secrets or sensitive data
- NEVER skip security scans without justification

❌ **Workflow Anti-Patterns**:

- NEVER use `@main` for consumer references (use a date tag like `@2026-04-25`)
- NEVER duplicate logic across workflows (use composite actions)
- NEVER hard-code values (use inputs)

---

## Related Documentation

- **[README.md](./README.md)** - User-facing workflow documentation
- **[CHANGELOG.md](./CHANGELOG.md)** - Version history and changes
- **[REVIEW.md](./REVIEW.md)** - Code review guidelines for this repository
- **Renovate Presets**: `renovate-*.json` files in repository root

---

## Renovate Preset Conventions

**Gotchas when editing the Renovate presets**:

- Repo-level Renovate config for this repo lives in the root `renovate.json`
  and nowhere else. Renovate reads the **first** config file it finds, and
  `renovate.json` / `renovate.json5` is checked before their `.github/`
  counterparts (`.renovaterc*` comes last) — so a `customManagers` or
  `packageRules` block added to `.github/renovate.json` while the root file
  exists never runs. Add repo-level managers to the root file; do not recreate
  `.github/renovate.json`.
- This repo's own `renovate.json` MUST use the `#main` suffix when extending
  its own presets: `github>sbaerlocher/.github:renovate-base#main`. Without
  `#main`, Renovate may resolve to an older pinned commit of this repo.
  Consumer repos should omit `#main` and use the default resolution.
- `lockFileMaintenance` is a top-level scheduler, not a package rule —
  it does **not** belong inside `packageRules`.
- JS framework group rules (Svelte, Vue, React, …) need explicit
  `matchPackageNames` entries; otherwise major updates are not captured.

---

## Maintenance Tasks

### Weekly

- Review Renovate PRs for action updates
- Check consumer repository workflow runs

### Monthly

- Review workflow execution times
- Identify optimization opportunities
- Update documentation

### Quarterly

- Review all workflows for deprecations
- Update to latest action versions
- Security audit

---

## Contact & Support

**Repository Owner**: Simon Bärlocher (@sbaerlocher)
**Issues**: [GitHub Issues](https://github.com/sbaerlocher/.github/issues)
**Website**: [sbaerlocher.ch](https://sbaerlocher.ch)

---

**Last Updated**: 2026-07-18
**Version**: 1.4.0

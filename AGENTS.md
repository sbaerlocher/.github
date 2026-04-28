# Reusable GitHub Actions Workflows

**Repository Type**: Centralized Workflow Repository
**Purpose**: Provide reusable GitHub Actions workflows for all sbaerlocher projects
**Visibility**: Public
**Last Updated**: 2026-04-28

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

- **Total Workflows**: 22 reusable workflows (see [.github/workflows/](./.github/workflows/))
- **Categories**: CI (5), Security (6), Deploy (2), Release (4), Operations (1), AI (2), E2E (2)
- **Consumers**: applications, infrastructure, authentication, observability, functions,
  sbaerlocher.ch, tsmetrics, and more

---

## Important Standards & Conventions

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
- New tags are cut from `main` after a batch of changes has settled. The
  cadence is documented in `CHANGELOG.md`.
- Renovate updates date tags in consumer repos automatically via the
  custom manager defined in `renovate-base.json`.

---

## Workflow Categories

### CI - Continuous Integration (5)

**Purpose**: Validate code quality, tests, and security before merge

| Workflow       | File               | Description               | Languages/Tools                 |
| -------------- | ------------------ | ------------------------- | ------------------------------- |
| CI (Ansible)   | `ci-ansible.yml`   | Ansible syntax & lint     | Ansible, ansible-lint           |
| CI (GitOps)    | `ci-gitops.yml`    | Fleet & K8s validation    | Fleet, Helm, kubeconform        |
| CI (Go)        | `ci-go.yml`        | Go build, test & security | Go, golangci-lint, gosec        |
| CI (JS/TS)     | `ci-js.yml`        | Quality, tests & security | JS/TS, Prettier, ESLint, Vitest |
| CI (Terraform) | `ci-terraform.yml` | Terraform validation      | Terraform, tflint               |

**Key Features**:

- Parallel execution (quality + tests)
- Smart caching (dependencies, build artifacts)
- Conditional security scans
- Typical runtime: 5-12 minutes

### Security - Scanning & Analysis (6)

**Purpose**: Comprehensive security scanning (SAST, secrets, dependencies, containers)

| Workflow        | File                        | Description                | Tools                   |
| --------------- | --------------------------- | -------------------------- | ----------------------- |
| SAST            | `security-code.yml`         | Static code analysis       | CodeQL (multi-language) |
| Config Security | `security-config.yml`       | IaC security               | Checkov, Kubeconform    |
| Dependencies    | `security-deps.yml`         | Dependency vulnerabilities | govulncheck, npm audit  |
| Secrets         | `security-secrets.yml`      | Secret detection           | Gitleaks, TruffleHog    |
| Containers      | `security-containers.yml`   | Container scanning         | Trivy, Grype            |
| Supply Chain    | `security-sbom.yml`         | SBOM & signing             | Cosign, CycloneDX       |

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

### Operations - Operational Tasks (1)

**Purpose**: Scheduled maintenance and operational tasks

| Workflow      | File                              | Description          | Schedule  |
| ------------- | --------------------------------- | -------------------- | --------- |
| Orchestration | `ops-terraform-orchestration.yml` | Multi-environment TF | On-demand |

### AI - AI-Assisted Workflows (2)

**Purpose**: AI-powered code review and on-demand assistance (private repos only)

| Workflow    | File                   | Description                        |
| ----------- | ---------------------- | ---------------------------------- |
| Code Review | `ai-claude-review.yml` | Auto code review (reads REVIEW.md) |
| On-demand   | `ai-claude.yml`        | On-demand @claude mentions         |

### E2E - End-to-End Tests (2)

**Purpose**: End-to-end testing with Docker Compose or whatwedo dde

| Workflow   | File             | Description                                                     |
| ---------- | ---------------- | --------------------------------------------------------------- |
| E2E Docker | `e2e-docker.yml` | E2E tests via Docker Compose + Playwright                       |
| E2E dde    | `e2e-dde.yml`    | E2E tests via whatwedo `dde project:up` + Playwright (Linux)    |

`e2e-dde.yml` is the dde-native counterpart to `e2e-docker.yml`. Inputs
overlap (Playwright/Node setup is identical); the stack-management surface
swaps `compose-file` / `compose-profile` for `project-directory` /
`wait-url`. Linux-only (`dde system:install` requires Docker, which hosted
macOS runners don't ship).

### Internal Self-Tests (1)

**Purpose**: Smoke-test composite actions in this repo when their sources
change. Not reusable from consumer repos.

| Workflow         | File                     | Description                            |
| ---------------- | ------------------------ | -------------------------------------- |
| Test dde actions | `test-actions-dde.yml`   | Smoke-test `setup-dde` on Linux/macOS  |

---

## Composite Actions

Located under [`.github/actions/`](./.github/actions/). Consume from any
workflow via `sbaerlocher/.github/.github/actions/<name>@<DATE-TAG>`.

| Action       | File                            | Purpose                                                       |
| ------------ | ------------------------------- | ------------------------------------------------------------- |
| `setup-dde`  | `.github/actions/setup-dde/`    | Install whatwedo dde CLI; optional mkcert + `system:install`  |
| `project-up` | `.github/actions/project-up/`   | Install dde + `system:install` + `dde project:up` for E2E     |
| `sbom-npm`   | `.github/actions/sbom-npm/`     | CycloneDX SBOM for npm/pnpm/yarn/bun (internal helper)        |

### dde actions (`setup-dde`, `project-up`)

`setup-dde` downloads the dde binary from
[`whatwedo/dde`](https://github.com/whatwedo/dde) GitHub releases, verifies
SHA256 against `checksums.txt`, places it on `PATH`, and optionally installs
`mkcert` and runs `sudo --preserve-env=HOME,USER,DDE_CONFIG_DIR,DDE_DATA_DIR dde
system:install` (HOME preserved so mkcert installs the CA into the runner
user's trust store, not `/root`).

`project-up` is a thin wrapper: it `uses: ./.github/actions/setup-dde` with
`system-install: 'true'`, then runs `dde project:up` in the supplied
`working-directory`, then optionally polls `wait-url`. The relative `uses:`
inside a composite action resolves against the action's own repo, so this
works both for cross-repo consumers and for this repo's self-test workflow.

Reusable workflows (`e2e-dde.yml`) reference the actions via the full
versioned path (`sbaerlocher/.github/.github/actions/project-up@<DATE-TAG>`)
because a reusable workflow's `uses: ./...` resolves against the caller's
workspace, not the workflow's repo.

Composite actions have no `post:` hook, so cleanup is always an explicit
`if: always() run: dde project:down` step in the consumer workflow.

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
3. **Breaking Changes**: Cut a new dated tag and call out the break in
   `CHANGELOG.md` so consumers know not to bump until they migrate
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
│   ├── workflows/           # 22 reusable workflows + 1 internal self-test
│   │   ├── ai-*.yml        # AI workflows
│   │   ├── ci-*.yml        # CI workflows
│   │   ├── deploy-*.yml    # Deploy workflows
│   │   ├── e2e-*.yml       # End-to-end test workflows
│   │   ├── ops-*.yml       # Operations workflows
│   │   ├── release-*.yml   # Release workflows
│   │   ├── security-*.yml  # Security workflows
│   │   └── test-*.yml      # Internal self-tests (NOT reusable)
│   ├── ISSUE_TEMPLATE/     # Org-default issue forms
│   ├── CODEOWNERS          # Repository owners
│   ├── pull_request_template.md
│   └── renovate.json       # Renovate configuration
├── AGENTS.md               # AI agent documentation (this file)
├── CLAUDE.md               # Claude Code import
├── README.md               # Human-readable documentation
├── CHANGELOG.md            # Version history
├── SECURITY.md             # Org-default security policy
├── STANDARDS.md            # Repository standards
├── SETUP.md                # GitHub repo setup commands & branch rulesets
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
- **[STANDARDS.md](./STANDARDS.md)** - Repository standards for all projects
- **[CHANGELOG.md](./CHANGELOG.md)** - Version history and changes
- **[REVIEW.md](./REVIEW.md)** - Code review guidelines for this repository
- **Renovate Presets**: `renovate-*.json` files in repository root

---

## Renovate Preset Conventions

**Gotchas when editing the Renovate presets**:

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

**Last Updated**: 2026-04-28
**Version**: 1.3.0

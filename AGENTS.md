# Reusable GitHub Actions Workflows

**Repository Type**: Centralized Workflow Repository
**Purpose**: Provide reusable GitHub Actions workflows for all sbaerlocher projects
**Visibility**: Public
**Last Updated**: 2026-02-14

---

## Context for AI Agents

This repository contains centralized, reusable GitHub Actions workflows that are used across all repositories in the sbaerlocher organization. When working on this repository, you are directly impacting the CI/CD pipelines of multiple projects.

### What This Repository Does

**Centralized Workflow Management**:

- Provides reusable workflows for CI, Security, Deployment, and Release operations
- Eliminates workflow duplication across 10+ repositories
- Ensures consistent CI/CD behavior across all projects
- Simplifies workflow maintenance (fix once, benefits all repos)

**Current Statistics**:

- **Total Workflows**: 27 reusable workflows (see [.github/workflows/](./.github/workflows/))
- **Categories**: CI (3), Security (6), Deploy (2), Release (4), Operations (3), Other (9)
- **Consumers**: applications, infrastructure, authentication, observability, functions, sbaerlocher.ch, tsmetrics, and more

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
- `docs-*.yml` - Documentation workflows

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

**Recommended**: Use version tags (`@v1`) for stable references

```yaml
# Consumer repository
uses: sbaerlocher/.github/.github/workflows/ci-js.yml@v1
```

**Not Recommended**: Using `@main` (breaking changes affect all repos immediately)

**Tagging Strategy**:

- Major versions: `v1`, `v2` (updated via Renovate or manually)
- Point releases: `v1.0.0`, `v1.1.0` (documented in CHANGELOG.md)

---

## Workflow Categories

### CI - Continuous Integration (3)

**Purpose**: Validate code quality, tests, and security before merge

| Workflow | File | Description | Languages/Tools |
|----------|------|-------------|-----------------|
| CI (Go) | [ci-go.yml](./.github/workflows/ci-go.yml) | Go build, test & security | Go, golangci-lint, gosec |
| CI (JS/TS) | [ci-js.yml](./.github/workflows/ci-js.yml) | All-in-one: quality, tests, security | JS/TS, Prettier, ESLint, Vitest |
| CI (Terraform) | [ci-terraform.yml](./.github/workflows/ci-terraform.yml) | Terraform validation | Terraform, tflint, yamllint |

**Key Features**:

- Parallel execution (quality + tests)
- Smart caching (dependencies, build artifacts)
- Conditional security scans
- Typical runtime: 5-12 minutes

### Security - Scanning & Analysis (6)

**Purpose**: Comprehensive security scanning (SAST, secrets, dependencies, containers)

| Workflow | File | Description | Tools |
|----------|------|-------------|-------|
| SAST | [security-code.yml](./.github/workflows/security-code.yml) | Static code analysis | CodeQL (multi-language) |
| Config Security | [security-config.yml](./.github/workflows/security-config.yml) | IaC security | Checkov, Kubeconform |
| Dependencies | [security-deps.yml](./.github/workflows/security-deps.yml) | Dependency vulnerabilities | govulncheck, npm audit |
| Secrets | [security-secrets.yml](./.github/workflows/security-secrets.yml) | Secret detection | Gitleaks, TruffleHog |
| Containers | [security-containers.yml](./.github/workflows/security-containers.yml) | Container scanning | Trivy, Grype |
| Supply Chain | [security-supply-chain.yml](./.github/workflows/security-supply-chain.yml) | SBOM & signing | Cosign, CycloneDX |

**Strategy**:

- **PR**: CodeQL only (fast feedback)
- **Weekly**: Deep scans (scheduled Monday 02:00 UTC)
- **Public Repos**: SARIF upload to GitHub Security tab (free)
- **Private Repos**: Artifact upload (JSON/Table format)

### Deploy - Deployment Operations (2)

**Purpose**: Deploy infrastructure and applications

| Workflow | File | Description | Use Case |
|----------|------|-------------|----------|
| Terraform Deploy | [deploy-terraform.yml](./.github/workflows/deploy-terraform.yml) | Terraform plan & apply | IaC deployments |
| Cloudflare Workers | [deploy-cloudflare-workers.yml](./.github/workflows/deploy-cloudflare-workers.yml) | Wrangler deploy | Serverless functions |

**Features**:

- Bitwarden Secrets Manager integration
- Environment-based deployments
- Approval gates for production

### Release - Release Management (4)

**Purpose**: Build and publish versioned artifacts

| Workflow | File | Description | Output |
|----------|------|-------------|--------|
| Go Release | [release-go.yml](./.github/workflows/release-go.yml) | GoReleaser | Binaries (multi-platform) |
| Docker Release | [release-docker.yml](./.github/workflows/release-docker.yml) | Docker build & push | Container images |
| Helm Release | [release-helm.yml](./.github/workflows/release-helm.yml) | Helm chart publish | OCI charts |
| NPM Release | [release-npm.yml](./.github/workflows/release-npm.yml) | NPM publish | Package with provenance |

**Trigger**: `push` events on tags (`v*`)

### Operations - Operational Tasks (3)

**Purpose**: Scheduled maintenance and operational tasks

| Workflow | File | Description | Schedule |
|----------|------|-------------|----------|
| Drift Detection | [ops-drift-detection.yml](./.github/workflows/ops-drift-detection.yml) | Terraform drift | Weekly Monday 06:00 UTC |
| Secret Sync | [ops-sync-secrets.yml](./.github/workflows/ops-sync-secrets.yml) | Bitwarden → CF Workers | On-demand |
| Orchestration | [ops-terraform-orchestration.yml](./.github/workflows/ops-terraform-orchestration.yml) | Multi-environment TF | On-demand |

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
2. **Consumer Testing**: Test in 1-2 consumer repos with test workflow
3. **Breaking Changes**: Increment major version tag (`v1` → `v2`)
4. **Non-Breaking**: Can update existing version tag
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
    uses: sbaerlocher/.github/.github/workflows/ci-js.yml@v1
    with:
      package-manager: pnpm
      enable-security-scans: true
      enable-dependency-review: true
    secrets:
      CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}
```

### Required Secrets in Consumer Repos

**Common Secrets**:

| Secret | Purpose | Required For |
|--------|---------|--------------|
| `BW_ACCESS_TOKEN` | Bitwarden Secrets Manager | Terraform/Workers deploy |
| `CODECOV_TOKEN` | Code coverage upload | CI workflows |
| `CLAUDE_CODE_OAUTH_TOKEN` | AI code review | Private repos only |

---

## Troubleshooting

### Workflow Not Found Error

```
Error: Unable to resolve action sbaerlocher/.github/.github/workflows/ci-js.yml@main
```

**Solution**: Check the nested path structure

```yaml
uses: sbaerlocher/.github/.github/workflows/ci-js.yml@v1
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
│   ├── workflows/           # 27 reusable workflows
│   │   ├── ci-*.yml        # CI workflows
│   │   ├── security-*.yml  # Security workflows
│   │   ├── deploy-*.yml    # Deploy workflows
│   │   ├── release-*.yml   # Release workflows
│   │   ├── ops-*.yml       # Operations workflows
│   │   ├── ai-*.yml        # AI workflows
│   │   └── docs-*.yml      # Documentation workflows
│   ├── actions/            # Custom composite actions
│   ├── CODEOWNERS          # Repository owners
│   └── renovate.json       # Renovate configuration
├── AGENTS.md               # AI agent documentation (this file)
├── CLAUDE.md               # Claude Code import
├── README.md               # Human-readable documentation
├── CHANGELOG.md            # Version history
├── STANDARDS.md            # Repository standards
├── LICENSE                 # MIT License
├── .editorconfig           # Editor consistency
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

❌ **Breaking Changes Without Versioning**:

- NEVER make breaking changes to existing workflows without incrementing version
- NEVER remove inputs/outputs without deprecation notice
- NEVER change default behavior without testing impact

❌ **Security Anti-Patterns**:

- NEVER use tag-only action references (`@v4`)
- NEVER log secrets or sensitive data
- NEVER skip security scans without justification

❌ **Workflow Anti-Patterns**:

- NEVER use `@main` for consumer references (use `@v1`)
- NEVER duplicate logic across workflows (use composite actions)
- NEVER hard-code values (use inputs)

---

## Related Documentation

- **[README.md](./README.md)** - User-facing workflow documentation
- **[STANDARDS.md](./STANDARDS.md)** - Repository standards for all projects
- **[CHANGELOG.md](./CHANGELOG.md)** - Version history and changes
- **Renovate Presets**: `renovate-*.json` files in repository root

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
**Website**: https://sbaerlocher.ch

---

**Last Updated**: 2026-02-14
**Version**: 1.1.0

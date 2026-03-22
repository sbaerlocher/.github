# Reusable GitHub Actions Workflows

**Model:** Rolling Release
**Total Workflows:** 27 (consolidated from 30+)
**Last Updated:** 2026-02-14

---

## 🚀 Quick Start

### JavaScript/TypeScript Projects

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
  push:
    branches: [main]

jobs:
  ci:
    uses: sbaerlocher/.github/.github/workflows/ci-js.yml@v1
    with:
      package-manager: pnpm
      enable-security-scans: true
    secrets:
      CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}
```

### Go Projects

```yaml
# .github/workflows/ci.yml
jobs:
  ci:
    uses: sbaerlocher/.github/.github/workflows/ci-go.yml@v1
    with:
      go-version: '1.25'
```

### Terraform Projects

```yaml
# .github/workflows/ci.yml
jobs:
  terraform:
    uses: sbaerlocher/.github/.github/workflows/ci-terraform.yml@v1

# .github/workflows/deploy.yml (on: push main)
jobs:
  deploy:
    uses: sbaerlocher/.github/.github/workflows/deploy-terraform.yml@v1
    with:
      environment: 'production'
      bw-secrets: |
        <uuid> > ENV_VAR
    secrets:
      BW_ACCESS_TOKEN: ${{ secrets.BW_ACCESS_TOKEN }}
```

---

## 📂 Workflow Categories

### CI - Continuous Integration (4)

- **[ci-ansible.yml](./.github/workflows/ci-ansible.yml)** - Ansible Linting & Validation
- **[ci-go.yml](./.github/workflows/ci-go.yml)** - Go Build, Test & Security
- **[ci-js.yml](./.github/workflows/ci-js.yml)** - JavaScript/TypeScript All-in-One
- **[ci-terraform.yml](./.github/workflows/ci-terraform.yml)** - Terraform Validation

### Security - Scanning & Analysis (6)

- **[security-code.yml](./.github/workflows/security-code.yml)** - SAST (CodeQL Multi-Language)
- **[security-config.yml](./.github/workflows/security-config.yml)** - Infrastructure Config (TF/K8s/Ansible)
- **[security-deps.yml](./.github/workflows/security-deps.yml)** - Dependencies & Licenses
- **[security-secrets.yml](./.github/workflows/security-secrets.yml)** - Secret Detection
- **[security-containers.yml](./.github/workflows/security-containers.yml)** - Container Security
- **[security-supply-chain.yml](./.github/workflows/security-supply-chain.yml)** - SBOM & Signing

### Deploy - Deployment Operations (2)

- **[deploy-terraform.yml](./.github/workflows/deploy-terraform.yml)** - Terraform Deployment
- **[deploy-cloudflare-workers.yml](./.github/workflows/deploy-cloudflare-workers.yml)** - Cloudflare Workers

### Release - Release Management (4)

- **[release-go.yml](./.github/workflows/release-go.yml)** - Go Binary Release (GoReleaser)
- **[release-helm.yml](./.github/workflows/release-helm.yml)** - Helm Chart Release
- **[release-docker.yml](./.github/workflows/release-docker.yml)** - Docker Image Build & Push
- **[release-npm.yml](./.github/workflows/release-npm.yml)** - NPM Package with Provenance

### Operations - Operational Tasks (4)

- **[drift-terraform.yml](./.github/workflows/drift-terraform.yml)** - Terraform Drift Detection (Legacy)
- **[ops-drift-detection.yml](./.github/workflows/ops-drift-detection.yml)** - Terraform Drift Detection
- **[ops-sync-secrets.yml](./.github/workflows/ops-sync-secrets.yml)** - Cloudflare Workers Secret Sync
- **[ops-terraform-orchestration.yml](./.github/workflows/ops-terraform-orchestration.yml)** - Multi-Environment

### Testing & Quality (3)

- **[e2e-docker.yml](./.github/workflows/e2e-docker.yml)** - E2E Testing with Docker Compose
- **[helm-test.yml](./.github/workflows/helm-test.yml)** - Helm Chart Testing with Kind
- **[quality-benchmarks.yml](./.github/workflows/quality-benchmarks.yml)** - Performance Benchmarking

### Other (4)

- **AI**: [ai-claude.yml](./.github/workflows/ai-claude.yml), [ai-claude-review.yml](./.github/workflows/ai-claude-review.yml)
- **Docs**: [docs-terraform.yml](./.github/workflows/docs-terraform.yml)
- **Notify**: [notify-deployment.yml](./.github/workflows/notify-deployment.yml)

---

## 🎯 Key Features

### 1. Consolidation Strategy

**Security Workflows**: 9 → 6 (-33% complexity, +100% coverage)

- Multi-language support (Go + JS/TS + Python in one workflow)
- Multi-tool defense (Trivy + Grype, Gitleaks + TruffleHog)
- Supply chain security (SBOM + Cosign signing)

**JavaScript CI**: 3 → 1

- All-in-one workflow with smart conditionals
- Quality + Tests + Security in one call
- Supports pnpm, npm, yarn, bun

### 2. Enterprise-Grade Security

- **SAST**: CodeQL for 6+ languages
- **Secrets**: Gitleaks + TruffleHog
- **Dependencies**: govulncheck, npm audit, safety
- **Containers**: Trivy + Grype
- **Licenses**: Compliance for Go, JS/TS, Python
- **SBOM**: CycloneDX + SPDX formats
- **Signing**: Cosign keyless signing

### 3. Performance Optimized

- Parallel security scans (matrix strategy)
- Smart caching (dependencies + Turborepo)
- Conditional execution (skip unnecessary scans)
- Typical CI time: 5-12 minutes

### 4. Production Ready

- SARIF upload for GitHub Security tab
- PR comments for dependency review
- Fail-on-findings options
- Comprehensive summary reports

---

## 📖 Usage Examples

### Complete CI/CD Pipeline (JavaScript)

```yaml
# .github/workflows/ci.yml
name: CI
on: [pull_request, push]

jobs:
  ci:
    uses: sbaerlocher/.github/.github/workflows/ci-js.yml@v1
    with:
      package-manager: pnpm
      enable-security-scans: true
      enable-dependency-review: true

# .github/workflows/security.yml
name: Security
on:
  schedule:
    - cron: '0 6 * * *'  # Daily at 6 AM UTC

jobs:
  code-analysis:
    uses: sbaerlocher/.github/.github/workflows/security-code.yml@v1
    with:
      languages: '["javascript-typescript"]'

  deps-and-licenses:
    uses: sbaerlocher/.github/.github/workflows/security-deps.yml@v1
    with:
      language: 'javascript'
      enable-license-check: true

  secret-detection:
    uses: sbaerlocher/.github/.github/workflows/security-secrets.yml@v1

# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: sbaerlocher/.github/.github/workflows/deploy-cloudflare-workers.yml@v1
    with:
      workers: '["worker1", "worker2"]'
      package-manager: pnpm
    secrets:
      BW_ACCESS_TOKEN: ${{ secrets.BW_ACCESS_TOKEN }}

# .github/workflows/release.yml
name: Release
on:
  push:
    tags: ['v*']

jobs:
  release:
    uses: sbaerlocher/.github/.github/workflows/release-npm.yml@v1

  sbom:
    uses: sbaerlocher/.github/.github/workflows/security-supply-chain.yml@v1
    with:
      artifact-type: 'npm-package'
      artifact-ref: '.'
      enable-sbom: true
```

---

## 📋 Project Type Guide

### Required Workflows by Repository Type

| Repository Type                | Required Workflows                                                                                      | Optional Workflows                                                      | Triggers              |
| ------------------------------ | ------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- | --------------------- |
| **JavaScript/TypeScript**      | `ci.yml` (ci-js)<br>`security.yml` (code-analysis)                                                      | `release.yml` (release-npm)<br>`deploy.yml` (deploy-cloudflare-workers) | PR, Push, Weekly      |
| **Go Projects**                | `ci.yml` (ci-go)<br>`security.yml` (code-analysis)                                                      | `release.yml` (release-go, release-docker)                              | PR, Push, Weekly      |
| **Infrastructure (Terraform)** | `ci.yml` (ci-terraform)<br>`deploy.yml` (deploy-terraform)<br>`security.yml` (config-scan, secret-scan) | `drift.yml` (drift-detection)<br>`docs.yml` (terraform-docs)            | PR, Push main, Weekly |
| **GitOps (Fleet/Helm)**        | `ci.yml` (fleet/helm validation)<br>`deploy.yml` (fleet sync)<br>`security.yml` (config-scan)           | -                                                                       | PR, Push main         |
| **Packages (NPM/Go)**          | `ci.yml`<br>`release.yml`<br>`security.yml`                                                             | -                                                                       | PR, Tag push          |
| **Serverless (CF Workers)**    | `ci.yml` (ci-js)<br>`deploy.yml` (deploy-cloudflare-workers)<br>`security.yml`                          | `ops/sync-secrets.yml`                                                  | PR, Push main         |

### Security Requirements

**Public Repositories:**

- ✅ **Required**: `security.yml` with `code-analysis` job (CodeQL)
- ✅ **Recommended**: Weekly scheduled security scans
- ✅ **SARIF Upload**: Free GitHub Security tab integration

**Private Repositories:**

- 🔧 **Optional**: `security.yml` (requires GitHub Advanced Security license for SARIF)
- ✅ **Recommended**: `claude.yml` + `claude-code-review.yml` for AI assistance
- 📝 **Note**: Artifact uploads work without license

---

## 📚 Workflow Reference

### CI Workflows

#### ci-go.yml

**Purpose**: Go project validation, testing & security
**When to use**: All Go projects
**Triggers**: `pull_request`, `workflow_call`

```yaml
jobs:
  ci:
    uses: sbaerlocher/.github/.github/workflows/ci-go.yml@v1
    with:
      go-version: '1.25'
      enable-security-scans: true
```

**Features**:

- Build & Test with coverage
- golangci-lint + gofmt
- gosec + govulncheck security scans
- Parallel matrix execution

---

#### ci-js.yml

**Purpose**: JavaScript/TypeScript all-in-one validation
**When to use**: JS/TS, Vue, React, Astro, Node.js projects
**Triggers**: `pull_request`, `workflow_call`

```yaml
jobs:
  ci:
    uses: sbaerlocher/.github/.github/workflows/ci-js.yml@v1
    with:
      package-manager: pnpm
      enable-security-scans: true
      enable-dependency-review: true
```

**Features**:

- Quality: Prettier, ESLint, Type-checking
- Tests: Vitest with coverage
- Security: npm audit, dependency review
- Smart caching (pnpm/npm/yarn/bun)

---

#### ci-terraform.yml

**Purpose**: Terraform validation
**When to use**: All Terraform/IaC projects
**Triggers**: `pull_request`, `workflow_call`

```yaml
jobs:
  terraform:
    uses: sbaerlocher/.github/.github/workflows/ci-terraform.yml@v1
    with:
      terraform-version: '1.14.3'
```

**Features**:

- terraform fmt, validate
- tflint scanning
- YAML validation
- Multi-environment support

---

### Security Workflows

#### security-code.yml

**Purpose**: SAST (Static Application Security Testing) with CodeQL
**When to use**: **Required for public repos**, optional for private
**Triggers**: `pull_request`, `push`, `schedule`

```yaml
jobs:
  code-analysis:
    uses: sbaerlocher/.github/.github/workflows/security-code.yml@v1
    with:
      languages: '["javascript-typescript", "go", "python"]'
```

**Supported Languages**:

- JavaScript/TypeScript
- Go, Python, Java
- C/C++, C#, Ruby

**Features**:

- Multi-language parallel scanning
- SARIF upload to GitHub Security tab
- CVE detection in code logic

---

#### security-config.yml

**Purpose**: Infrastructure-as-Code security scanning
**When to use**: Terraform, Kubernetes, Ansible projects
**Triggers**: `schedule` (weekly)

```yaml
jobs:
  config-scan:
    uses: sbaerlocher/.github/.github/workflows/security-config.yml@v1
    with:
      scan-terraform: true
      scan-kubernetes: true
```

**Features**:

- Checkov (Terraform/K8s)
- Kubeconform validation
- Ansible-lint
- Best practices enforcement

---

#### security-secrets.yml

**Purpose**: Secret detection in code
**When to use**: All repositories
**Triggers**: `schedule` (weekly), `workflow_dispatch`

```yaml
jobs:
  secret-scan:
    uses: sbaerlocher/.github/.github/workflows/security-secrets.yml@v1
```

**Features**:

- Gitleaks + TruffleHog (dual scanners)
- API keys, passwords, tokens detection
- SARIF results

---

#### security-deps.yml

**Purpose**: Dependency vulnerability scanning
**When to use**: Projects with dependencies (Go, JS/TS, Python)
**Triggers**: `schedule` (weekly)

```yaml
jobs:
  dependency-scan:
    uses: sbaerlocher/.github/.github/workflows/security-deps.yml@v1
    with:
      language: 'javascript'
      enable-license-check: true
```

**Features**:

- govulncheck (Go), npm audit (JS), safety (Python)
- License compliance checking
- Dependency review on PRs

---

#### security-containers.yml

**Purpose**: Container image security scanning
**When to use**: Projects building Docker images
**Triggers**: `schedule` (weekly)

```yaml
jobs:
  container-scan:
    uses: sbaerlocher/.github/.github/workflows/security-containers.yml@v1
    with:
      image: 'ghcr.io/user/app:latest'
```

**Features**:

- Trivy + Grype scanners
- CVE database scanning
- OS package vulnerabilities

---

#### security-supply-chain.yml

**Purpose**: SBOM generation & artifact signing
**When to use**: Release workflows, production deployments
**Triggers**: `workflow_call` (from release workflows)

```yaml
jobs:
  sbom:
    uses: sbaerlocher/.github/.github/workflows/security-supply-chain.yml@v1
    with:
      artifact-type: 'docker'
      artifact-ref: 'ghcr.io/user/app:v1.0.0'
      enable-sbom: true
      enable-signing: true
```

**Features**:

- CycloneDX + SPDX SBOM formats
- Cosign keyless signing
- Artifact attestation

---

### Deploy Workflows

#### deploy-terraform.yml

**Purpose**: Terraform plan & apply
**When to use**: Infrastructure/IaC deployments
**Triggers**: `push` (main branch), `workflow_dispatch`

```yaml
jobs:
  deploy:
    uses: sbaerlocher/.github/.github/workflows/deploy-terraform.yml@v1
    with:
      environment: 'production'
      terraform-version: '1.14.3'
      bw-secrets: |
        uuid-1 > TF_VAR_api_token
        uuid-2 > TF_VAR_password
    secrets:
      BW_ACCESS_TOKEN: ${{ secrets.BW_ACCESS_TOKEN }}
```

**Features**:

- Bitwarden Secrets Manager integration
- Terraform plan preview
- Apply with approval gates
- State locking

---

#### deploy-cloudflare-workers.yml

**Purpose**: Cloudflare Workers deployment
**When to use**: Serverless function deployments
**Triggers**: `push` (main), `workflow_dispatch`

```yaml
jobs:
  deploy:
    uses: sbaerlocher/.github/.github/workflows/deploy-cloudflare-workers.yml@v1
    with:
      workers: '["worker1", "worker2"]'
      package-manager: pnpm
    secrets:
      BW_ACCESS_TOKEN: ${{ secrets.BW_ACCESS_TOKEN }}
```

**Features**:

- Multi-worker matrix deployment
- Wrangler CLI
- Secret injection from Bitwarden
- Monorepo support (pnpm workspaces)

---

### Release Workflows

#### release-go.yml

**Purpose**: Go binary releases with GoReleaser
**When to use**: Go CLI tools, applications
**Triggers**: `push` (tags `v*`)

```yaml
jobs:
  release:
    uses: sbaerlocher/.github/.github/workflows/release-go.yml@v1
```

**Features**:

- Multi-platform binaries (Linux, macOS, Windows)
- GitHub Release creation
- Changelog generation
- Homebrew formula (optional)

---

#### release-docker.yml

**Purpose**: Multi-platform Docker image builds
**When to use**: Containerized applications
**Triggers**: `push` (tags `v*`)

```yaml
jobs:
  release:
    uses: sbaerlocher/.github/.github/workflows/release-docker.yml@v1
    with:
      image-name: 'ghcr.io/${{ github.repository }}'
      platforms: 'linux/amd64,linux/arm64'
```

**Features**:

- Multi-architecture builds (amd64, arm64)
- Push to GHCR/Docker Hub
- Provenance attestation
- Layer caching

---

#### release-helm.yml

**Purpose**: Helm chart publishing
**When to use**: Kubernetes applications
**Triggers**: `push` (tags `v*`)

```yaml
jobs:
  release:
    uses: sbaerlocher/.github/.github/workflows/release-helm.yml@v1
    with:
      chart-path: './charts/app'
```

**Features**:

- Helm package & push to OCI registry
- Chart validation
- Dependency updates
- Artifact signing

---

#### release-npm.yml

**Purpose**: NPM package publishing
**When to use**: JavaScript/TypeScript libraries
**Triggers**: `push` (tags `v*`)

```yaml
jobs:
  release:
    uses: sbaerlocher/.github/.github/workflows/release-npm.yml@v1
```

**Features**:

- Publish to npm registry
- Provenance attestation
- Package validation
- Automated versioning

---

### Operations Workflows

#### ops-drift-detection.yml

**Purpose**: Terraform state drift detection
**When to use**: Production Terraform deployments
**Triggers**: `schedule` (weekly Monday 06:00 UTC)

```yaml
jobs:
  drift:
    uses: sbaerlocher/.github/.github/workflows/ops-drift-detection.yml@v1
    with:
      environment: 'production'
    secrets:
      BW_ACCESS_TOKEN: ${{ secrets.BW_ACCESS_TOKEN }}
```

**Features**:

- Scheduled drift checks
- Slack/email notifications
- Detailed diff reports

---

#### ops-terraform-orchestration.yml

**Purpose**: Multi-environment Terraform orchestration
**When to use**: Complex infrastructure with dev/staging/prod
**Triggers**: `workflow_dispatch`, `workflow_call`

```yaml
jobs:
  orchestrate:
    uses: sbaerlocher/.github/.github/workflows/ops-terraform-orchestration.yml@v1
    with:
      environments: '["dev", "staging", "production"]'
```

**Features**:

- Sequential environment deployments
- Approval gates between environments
- Rollback capabilities

---

#### ops-sync-secrets.yml

**Purpose**: Sync secrets from Bitwarden to Cloudflare Workers
**When to use**: Cloudflare Workers with secrets
**Triggers**: `workflow_dispatch`, `schedule`

```yaml
jobs:
  sync:
    uses: sbaerlocher/.github/.github/workflows/ops-sync-secrets.yml@v1
    with:
      workers: '["worker1", "worker2"]'
      secrets-mapping: |
        uuid-1 > API_TOKEN
        uuid-2 > DATABASE_URL
```

**Features**:

- Bitwarden → Cloudflare Workers sync
- Matrix-based multi-worker updates
- Verification after sync

---

### Testing & Quality Workflows

#### e2e-docker.yml

**Purpose**: End-to-end testing using Docker Compose
**When to use**: Applications with Docker Compose configurations
**Triggers**: `pull_request`, `workflow_call`

```yaml
jobs:
  e2e:
    uses: sbaerlocher/.github/.github/workflows/e2e-docker.yml@v1
    with:
      compose-file: 'docker-compose.test.yml'
      test-command: 'npm run test:e2e'
```

**Features**:

- Docker Compose orchestration
- Service health checks
- Log collection on failure
- Cleanup after tests

---

#### helm-test.yml

**Purpose**: Helm chart validation and testing with Kind
**When to use**: Helm chart repositories
**Triggers**: `pull_request`, `workflow_call`

```yaml
jobs:
  helm-test:
    uses: sbaerlocher/.github/.github/workflows/helm-test.yml@v1
    with:
      chart-path: './charts/myapp'
```

**Features**:

- Helm lint validation
- Kind cluster deployment
- Chart installation testing
- Template rendering validation

---

#### quality-benchmarks.yml

**Purpose**: Performance benchmarking and regression detection
**When to use**: Performance-critical applications
**Triggers**: `pull_request`, `workflow_dispatch`

```yaml
jobs:
  benchmarks:
    uses: sbaerlocher/.github/.github/workflows/quality-benchmarks.yml@v1
    with:
      benchmark-command: 'go test -bench=. -benchmem'
```

**Features**:

- Automated benchmark execution
- Performance regression detection
- Historical comparison
- Results artifacts

---

#### notify-deployment.yml

**Purpose**: Send deployment notifications to communication channels
**When to use**: After successful deployments
**Triggers**: `workflow_call`

```yaml
jobs:
  notify:
    uses: sbaerlocher/.github/.github/workflows/notify-deployment.yml@v1
    with:
      environment: 'production'
      status: 'success'
    secrets:
      SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK }}
```

**Features**:

- Slack/Discord notifications
- Deployment status tracking
- Rich formatting with metadata
- Failure alerts

---

### AI & Documentation Workflows

#### ai-claude.yml

**Purpose**: On-demand @claude mentions in issues/PRs
**When to use**: Private repositories only
**Triggers**: `issue_comment`, `pull_request_review_comment`

```yaml
jobs:
  claude:
    uses: sbaerlocher/.github/.github/workflows/ai-claude.yml@v1
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

---

#### ai-claude-review.yml

**Purpose**: Automatic AI code review on PRs
**When to use**: Private repositories only
**Triggers**: `pull_request` (opened, synchronize)

```yaml
jobs:
  claude-review:
    uses: sbaerlocher/.github/.github/workflows/ai-claude-review.yml@v1
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

---

#### docs-terraform.yml

**Purpose**: Auto-generate Terraform documentation
**When to use**: Terraform modules with README
**Triggers**: `push` (main), `pull_request`

```yaml
jobs:
  docs:
    uses: sbaerlocher/.github/.github/workflows/docs-terraform.yml@v1
```

**Features**:

- terraform-docs generation
- Auto-commit to PR
- Module documentation

---

## ⚙️ Workflow Versioning

**Rolling Release Model**: This repository uses continuous deployment to `main`.

**Recommended Usage**:

```yaml
# Option 1: Rolling (always latest) - Use for development/testing
uses: sbaerlocher/.github/.github/workflows/ci-js.yml@main

# Option 2: Pinned commit SHA - Use for production stability
uses: sbaerlocher/.github/.github/workflows/ci-js.yml@a386f88

# Option 3: Date-based tags (if created) - Use for reproducible builds
uses: sbaerlocher/.github/.github/workflows/ci-js.yml@2026-02-14
```

**Best Practice**:

- Development: Use `@main` for latest features
- Production: Pin to specific commit SHA for stability
- Renovate will automatically update SHA references

---

## 🛠️ Troubleshooting

### Workflow Not Found

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

- pnpm-lock.yaml
- package-lock.json
- yarn.lock
- go.sum

---

## 📊 Workflow Statistics

```
Total Workflows:    27
Security:            6 (22%)  ← Primary focus
Release:             4 (15%)
CI:                  4 (15%)
Operations:          4 (15%)
Testing & Quality:   3 (11%)
Other:               6 (22%)

Consolidation:      -33% workflow complexity
Feature Coverage:   +100% (multi-language, multi-tool)
Avg CI Time:        5-12 minutes (PR → Main)
```

---

## 🤝 Contributing

This is a private workflow repository. For issues or questions:

1. Check [AGENTS.md](./AGENTS.md) for AI agent documentation
2. Review [CHANGELOG.md](./CHANGELOG.md) for recent updates
3. Create an issue in this repository

---

## 📝 License

MIT License - See individual project repositories for details

---

## 🔗 Related Resources

- **[sbaerlocher/STANDARDS.md](https://github.com/sbaerlocher/sbaerlocher/blob/main/STANDARDS.md)** - Repository standards & conventions
- **[GitHub Actions Documentation](https://docs.github.com/en/actions)** - Official GitHub Actions docs
- **[Reusable Workflows Guide](https://docs.github.com/en/actions/using-workflows/reusing-workflows)** - GitHub's official guide

---

**Maintained by:** Simon Bärlocher (@sbaerlocher)
**Powered by:** Claude Sonnet 4.5
**Last Updated:** 2026-02-14

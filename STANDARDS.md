# Repository Standards

## Principles

**Public vs Private Repos:**

| Aspect                  | Public          | Private                  |
| ----------------------- | --------------- | ------------------------ |
| LICENSE                 | MIT (Required)  | None (Rights with Owner) |
| `security.yml` (CodeQL) | Required        | Optional                 |
| Claude Workflows        | Not recommended | Recommended              |
| Other structure         | Identical       | Identical                |

---

## Recommended Minimal Structure

Focus on essentials - no unnecessary files.

```text
repository/
├── .github/
│   ├── workflows/
│   │   └── [project-specific].yml
│   ├── CODEOWNERS
│   └── renovate.json
├── AGENTS.md                      # AI instructions (main file)
├── CLAUDE.md                      # Only: @AGENTS.md
├── README.md                      # Main documentation
├── LICENSE                        # MIT License (public only)
├── .editorconfig                  # Editor consistency
├── .gitignore                     # Project-specific
└── [project files]
```

---

## Required Files

### 1. README.md

**Content (minimal):**

```markdown
# Project Name

Short description (1-2 sentences).

## Quick Start

[Commands to start]

## Structure

[Brief folder overview if needed]

## License

MIT License
```

**Avoid:**

- Badges (except npm/go packages)
- Long feature lists
- Code examples (belong in AGENTS.md or docs)

### 2. LICENSE (Public Repos Only)

MIT License for all public repos. Private repos don't need LICENSE (rights with owner).

```
MIT License

Copyright (c) [YEAR] [YOUR NAME]

Permission is hereby granted...
```

### 3. .editorconfig

See [templates/.editorconfig](https://github.com/sbaerlocher/sbaerlocher/tree/main/templates/.editorconfig)

### 4. .gitignore

Project-specific, keep minimal:

- Build outputs
- Dependencies (node_modules, .terraform)
- IDE files (.idea, .vscode)
- OS files (.DS_Store)
- **Secrets** (see Secret Management section)

### 5. .github/CODEOWNERS

```text
# Default owner
* @your-username
```

### 6. .github/renovate.json

Required for all repos. See base configuration in [.github/renovate/renovate-base.json](./renovate/renovate-base.json).

---

## Optional (Only When Useful)

### CHANGELOG.md

Only for:

- npm/go packages with versions
- Projects with releases

Format: Keep a Changelog

```markdown
# Changelog

## [1.0.0] - 2025-01-15

### Added

- Feature X

### Fixed

- Bug Y
```

### .github/workflows/

**Naming Convention:**

- Lowercase
- Hyphens instead of underscores
- Short and descriptive

**Workflow Names (`name:` field):**

- Always write out full names (no abbreviations)
- Example: `name: Continuous Integration` (not `CI`)
- Example: `name: Security Scanning` (not `Security`)
- Match the workflow names in the table below

**Action References (Security):**

Actions MUST be pinned to full commit SHA with version comment:

```yaml
# ✅ CORRECT - SHA pinned with version comment
uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4.1.1
uses: actions/setup-node@60edb5dd545a775178f52524783378180af0d1f8 # v4.0.2

# ❌ WRONG - Tag only (mutable, security risk)
uses: actions/checkout@v4
uses: actions/setup-node@v4.0.2
```

**Why SHA pinning?**

- **Immutable**: SHA cannot be changed after commit
- **Supply-chain security**: Protects against tag hijacking attacks
- **Audit trail**: Exact version is always traceable
- **GitHub recommendation**: For security-critical workflows

**Renovate handles updates**: With proper Renovate config, SHA references are automatically updated with new version comments.

**Renovate Configuration** (add to `renovate-base.json`):

```json
{
  "github-actions": {
    "pinDigests": true
  }
}
```

**Reusable Workflow References:**

Reusable workflows SHOULD use version tags (date-based) for reproducibility and control:

```yaml
# ✅ CORRECT - Date tag (recommended)
uses: sbaerlocher/.github/.github/workflows/ci-terraform.yml@2026-02-14

# ⚠️ DISCOURAGED - Branch reference (automatic updates, less control)
uses: sbaerlocher/.github/.github/workflows/ci-terraform.yml@2026-02-14
```

**Why version tags?**

- **Reproducible builds**: Same workflow version produces same results
- **Controlled updates**: Changes only when explicitly updated via tag
- **Rollback capability**: Easy to revert to previous working version
- **Clear versioning**: Date-based tags are human-readable

**Standard Workflows:**

All workflows are centralized as **Reusable Workflows** in `sbaerlocher/.github/.github/workflows/`:

| Category       | Workflow                           | Local File               | Reusable Workflow                 | Description                          |
| -------------- | ---------------------------------- | ------------------------ | --------------------------------- | ------------------------------------ |
| **CI**         | Continuous Integration (Go)        | `ci.yml`                 | `ci-go.yml`                       | Go tests, linting, validation        |
| **CI**         | Continuous Integration (JS/TS)     | `ci.yml`                 | `ci-js.yml`                       | All-in-one: quality, tests, security |
| **CI**         | Continuous Integration (Terraform) | `ci.yml`                 | `ci-terraform.yml`                | TF validate, fmt, tflint             |
| **Deploy**     | Deployment (Terraform)             | `deploy.yml`             | `deploy-terraform.yml`            | Terraform plan & apply               |
| **Deploy**     | Deployment (Cloudflare Workers)    | `deploy.yml`             | `deploy-cloudflare-workers.yml`   | Wrangler deploy                      |
| **Release**    | Release (Go)                       | `release.yml`            | `release-go.yml`                  | GoReleaser                           |
| **Release**    | Release (Docker)                   | `release.yml`            | `release-docker.yml`              | Multi-platform build & push          |
| **Release**    | Release (Helm)                     | `release.yml`            | `release-helm.yml`                | Helm chart publish                   |
| **Release**    | Release (NPM)                      | `release.yml`            | `release-npm.yml`                 | NPM publish with provenance          |
| **Security**   | SAST (Public)                      | `security.yml`           | `security-code.yml`               | CodeQL multi-language                |
| **Security**   | Config Security                    | `security.yml`           | `security-config.yml`             | Terraform, Kubernetes, Ansible       |
| **Security**   | Dependency Security                | `security.yml`           | `security-deps.yml`               | Go, JS/TS, Python + licenses         |
| **Security**   | Secret Detection                   | `security.yml`           | `security-secrets.yml`            | Gitleaks, TruffleHog                 |
| **Security**   | Container Security                 | `security.yml`           | `security-containers.yml`         | Trivy, Grype                         |
| **Security**   | Supply Chain                       | `security.yml`           | `security-supply-chain.yml`       | SBOM, Cosign signing                 |
| **Operations** | Drift Detection                    | `drift.yml`              | `ops-drift-detection.yml`         | Terraform drift detection            |
| **Operations** | Orchestration                      | -                        | `ops-terraform-orchestration.yml` | Multi-environment                    |
| **Operations** | Secret Sync                        | -                        | `ops-sync-secrets.yml`            | Bitwarden to CF Workers              |
| **Docs**       | Terraform Docs                     | `docs.yml`               | `docs-terraform.yml`              | Auto-generate TF docs                |
| **AI**         | Code Review (Private)              | `claude-code-review.yml` | `ai-claude-review.yml`            | AI code review                       |
| **AI**         | Assistant (Private)                | `claude.yml`             | `ai-claude.yml`                   | On-demand @claude                    |

**Workflow Consolidation Strategy:**

All workflows are now centralized as reusable workflows in `sbaerlocher/.github/.github/workflows/`:

- **Single Source of Truth**: One workflow definition, used by all projects
- **Consistent Behavior**: All projects get the same CI/CD experience
- **Easy Updates**: Fix once, benefits all repositories
- **Reduced Maintenance**: No need to update workflows in each project individually

**Key Benefits:**

1. **JavaScript CI**: Consolidated 3 workflows (quality, test, security) into 1 all-in-one workflow
2. **Security**: Multi-language support (Go + JS + Python in one workflow)
3. **Defense-in-Depth**: Multiple scanners (Trivy + Grype, Gitleaks + TruffleHog)
4. **Supply Chain Security**: SBOM generation and Cosign signing built-in

**Usage Pattern** (call centralized workflows):

```yaml
# .github/workflows/ci.yml
name: Continuous Integration
on:
  pull_request:
  workflow_call:

jobs:
  terraform:
    uses: sbaerlocher/.github/.github/workflows/ci-terraform.yml@2026-02-14
    with:
      terraform-version: '1.14.3'
```

**Complete Example** (Terraform Repository):

```yaml
# .github/workflows/ci.yml
name: Continuous Integration
on:
  pull_request:
  workflow_call:

jobs:
  terraform:
    uses: sbaerlocher/.github/.github/workflows/ci-terraform.yml@2026-02-14
    with:
      terraform-version: '1.14.3'

# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  ci:
    uses: ./.github/workflows/ci.yml

  deploy:
    needs: ci
    uses: sbaerlocher/.github/.github/workflows/deploy-terraform.yml@2026-02-14
    with:
      terraform-version: '1.14.3'
      environment: 'production'
    secrets:
      BW_ACCESS_TOKEN: ${{ secrets.BW_ACCESS_TOKEN }}

# .github/workflows/security.yml
name: Security Scan
on:
  schedule:
    - cron: '0 2 * * 1'  # Weekly Monday 02:00 UTC
  workflow_dispatch:

jobs:
  config-scan:
    uses: sbaerlocher/.github/.github/workflows/security-config.yml@2026-02-14
    with:
      scan-terraform: true

  secret-scan:
    uses: sbaerlocher/.github/.github/workflows/security-secrets.yml@2026-02-14

  dependency-scan:
    uses: sbaerlocher/.github/.github/workflows/security-deps.yml@2026-02-14
    with:
      language: 'go'
```

**Schedule Frequency:**

Scheduled workflows should run **weekly** (not daily) to minimize unnecessary workflow runs:

```yaml
schedule:
  - cron: '0 6 * * 1' # Weekly Monday 06:00 UTC
```

Common schedules:

- `drift.yml`: Monday 06:00 UTC
- `security.yml`: Monday 02:00 UTC

**Workflow Trigger Strategy (Avoid Duplicate Runs):**

To prevent workflows from running twice on the same code (once on PR, once on merge to main), use this pattern:

```yaml
# ✅ ci.yml - Only on PR and workflow_call
on:
  pull_request:
    branches: [main]
  workflow_call:

# ✅ deploy.yml - Only on push to main, calls ci.yml
on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  ci:
    name: Continuous Integration
    uses: ./.github/workflows/ci.yml

  deploy:
    name: Deploy
    needs: ci
    runs-on: ubuntu-latest
    # ... deployment steps
```

**Benefits:**

- CI runs once on PR (validation)
- Deploy runs once on merge (includes CI + deployment)
- No duplicate test/lint runs on main branch
- Cleaner workflow history

**Anti-Pattern (Avoid):**

```yaml
# ❌ WRONG - Runs twice (PR + push to main)
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
```

**ci.yml Structure:**

See [.github/workflows/ci.yml](./workflows/ci.yml)

**Benefits:**

- `workflow_call` enables reuse by other workflows
- `quality` and `test` run in parallel
- `build` only after both are green
- `format:check` validates formatting before other checks
- Faster feedback on failures

**By Repo Type:**

| Repo Type                | Required                               | Optional                | Notes                                                 |
| ------------------------ | -------------------------------------- | ----------------------- | ----------------------------------------------------- |
| **Software Projects**    | `ci.yml`, `release.yml`                | -                       | Produce releasable artifacts (Docker, Helm, Binaries) |
| **Infrastructure (IaC)** | `ci.yml`, `deploy.yml`, `security.yml` | `drift.yml`, `docs.yml` | Terraform IaC                                         |
| **GitOps**               | `ci.yml`, `deploy.yml`                 | -                       | Kubernetes via Fleet                                  |
| **Packages**             | `ci.yml`, `release.yml`                | -                       | NPM, Go, Python packages                              |
| **Serverless**           | `ci.yml`, `deploy.yml`                 | -                       | Cloudflare Workers                                    |

**Workflow Distinction:**

Software projects (like `tsmetrics`, `functions`) **release** artifacts - they use `release.yml`:

- Docker images pushed to registry
- Helm charts published to OCI registry
- Binaries released via GoReleaser
- Semantic versioning (v1.2.3)
- Triggered by git tags

Infrastructure projects (like `authentication`, `observability`) **deploy** infrastructure - they use `deploy.yml`:

- Terraform plan & apply
- Environment-based (dev, staging, prod)
- State-based (no versioned releases)
- Triggered by pushes to main or manual dispatch

**Notes**:

- **ci.yml**: All validation (YAML, Fleet, Terraform, Helm, Kubernetes manifests, tests)
  - Software: tests, linting, type-checking, security scans (gosec, govulncheck, trivy)
  - GitOps: yamllint, Fleet validation, Helm lint, kubeconform
  - IaC: yamllint, terraform fmt/validate, tflint
- **build.yml**: Build artifacts for testing (Software projects only)
  - Single-platform Docker build (linux/amd64)
  - Helm chart validation with Kind
  - Container structure tests
  - Not pushed to registry (test only)
- **release.yml**: Release artifacts (Software projects only)
  - Multi-platform Docker build (linux/amd64, linux/arm64)
  - Push to container registry
  - Publish Helm chart to OCI
  - Create GitHub Release with binaries
- **deploy.yml**: Deploy infrastructure (Infrastructure/GitOps projects only)
  - Terraform: plan & apply
  - GitOps: Fleet sync verification
- **drift.yml**: Scheduled drift detection for Terraform (optional)
- **security.yml**: Comprehensive security scanning (PR + scheduled + manual)
  - **Code Analysis**: Calls `security-code.yml` (CodeQL multi-language SAST - required for public repos)
  - **IaC/GitOps**: Calls `security-config.yml` (Terraform/K8s/Ansible security)
  - **All repos**: Calls `security-secrets.yml` (Gitleaks + TruffleHog)
  - **With dependencies**: Calls `security-deps.yml` (Language-specific: Go, JS/TS, Python)
  - **Strategy**: CodeQL runs on PR for fast feedback, deep scans run weekly

**Security Scanning Output:**

- **Public Repos**: SARIF upload to GitHub Security tab (free)
- **Private Repos**:
  - Artifact upload (JSON/Table format)
  - SARIF upload requires GitHub Advanced Security license
  - Use `exit-code: 0` for non-blocking scans

**Additionally for all repos**:

- **Public Repos**: `security.yml` with CodeQL job (Required)
- **Private Repos**: `claude.yml` + `claude-code-review.yml` (Recommended)

### Claude GitHub Actions (Private Repos)

Two workflows for AI-assisted development:

**1. claude-code-review.yml - Automatic Code Review**

See [.github/workflows/claude-code-review.yml](./workflows/claude-code-review.yml)

**2. claude.yml - On-Demand @claude Mentions**

See [.github/workflows/claude.yml](./workflows/claude.yml)

**Setup:**

1. OAuth Token: <https://console.anthropic.com>
2. Secret: Repository → Settings → Secrets → `CLAUDE_CODE_OAUTH_TOKEN`

**Why Private Repos Only?**

- OAuth Token is personal/paid
- On public repos anyone could trigger `@claude`

### Testing & Coverage

**Test Framework:** Vitest (for JS/TS projects)

**package.json Scripts:**

```json
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage"
  }
}
```

**vitest.config.ts:**

See [templates/vitest.config.ts](https://github.com/sbaerlocher/sbaerlocher/tree/main/templates/vitest.config.ts)

**Dependencies:**

```json
{
  "devDependencies": {
    "vitest": "^3.0.0",
    "@vitest/coverage-v8": "^3.0.0"
  }
}
```

**Codecov:** Coverage upload in CI with `codecov/codecov-action`.

### Renovate Configuration

Shared presets in root can be extended by other repos.

**Available Presets:**

| Preset               | Extends | Use For                 |
| -------------------- | ------- | ----------------------- |
| `renovate-base`      | -       | All repos (base config) |
| `renovate-js`        | base    | JS/TS projects          |
| `renovate-terraform` | base    | Terraform/IaC           |
| `renovate-gitops`    | base    | GitOps/Helm             |

**Usage in your repo's `.github/renovate.json`:**

```json
{
  "extends": ["github>sbaerlocher/.github:renovate/renovate-base"]
}
```

Or for JS/TS projects:

```json
{
  "extends": ["github>sbaerlocher/.github:renovate/renovate-js"]
}
```

See [templates/](https://github.com/sbaerlocher/sbaerlocher/tree/main/templates/) for copy-paste examples.

**Project → Preset Mapping:**

| Project          | Preset               | Reason                        |
| ---------------- | -------------------- | ----------------------------- |
| `applications`   | `renovate-gitops`    | Fleet/Helm GitOps             |
| `authentication` | `renovate-terraform` | Terraform/IaC                 |
| `infrastructure` | `renovate-gitops`    | Terraform + Ansible + K8s     |
| `observability`  | `renovate-terraform` | Terraform/IaC                 |
| `functions`      | `renovate-js`        | TypeScript/Cloudflare Workers |
| `sbaerlocher.ch` | `renovate-js`        | Astro/TypeScript              |
| `sbaerlo.ch`     | `renovate-js`        | Astro/TypeScript              |
| `vue.aareguru`   | `renovate-js`        | Vue/TypeScript                |
| `dotfiles`       | `renovate-base`      | Nix + GitHub Actions          |
| `helm-chart`     | `renovate-gitops`    | Helm Charts                   |
| `savvy`          | `renovate-base`      | Go                            |
| `tsmetrics`      | `renovate-base`      | Go                            |
| `loyalty-system` | `renovate-base`      | Go                            |

**Anti-Pattern (Never Do):**

```json
// ❌ WRONG - Duplicates base config inline instead of extending preset
{
  "extends": ["config:recommended", ":semanticCommits"],
  "schedule": ["before 6am on Monday"],
  "timezone": "Europe/Zurich",
  "labels": ["dependencies"],
  "prConcurrentLimit": 5
}

// ✅ CORRECT - Extend shared preset, only add project-specific rules
{
  "extends": ["github>sbaerlocher/.github:renovate/renovate-js"],
  "packageRules": [
    { "groupName": "astro", "matchPackageNames": ["/^astro/", "/^@astrojs/"] }
  ]
}
```

**Note:** `lockFileMaintenance` is disabled by default. Normal dependency updates and `vulnerabilityAlerts` already cover transitive dependencies.

### Extended Documentation (Larger Projects)

For more complex projects additionally:

| File                 | Purpose                                | When                                             |
| -------------------- | -------------------------------------- | ------------------------------------------------ |
| `README.md`          | Project overview, setup basics         | All repos - keep minimal, avoid excessive detail |
| `ARCHITECTURE.md`    | System design, components, decisions   | Infrastructure, monorepos                        |
| `OPERATIONS.md`      | Runbooks, troubleshooting, maintenance | Production services                              |
| `DEPLOYMENT.md`      | Deploy process, environments           | When more complex than 1 command                 |
| `.github/SECRETS.md` | Secrets documentation                  | **Required** when repo uses any secrets          |

**Naming:** Uppercase, English.

**ARCHITECTURE.md Content:** (from architect perspective)

- System overview (Mermaid diagram)
- Components and interfaces
- Tradeoffs and limitations
- Security concept

**OPERATIONS.md Content:**

- Monitoring & Alerts
- Troubleshooting guide
- Maintenance tasks
- Incident response

**.github/SECRETS.md Content:**

- Secret naming schema
- Architecture diagram (how secrets flow)
- GitHub repository secrets
- External secret store references (Bitwarden, Vault, etc.)
- Setup instructions
- Rotation checklist
- Troubleshooting

### CONTRIBUTING.md

| Repo Type   | Required                                          |
| ----------- | ------------------------------------------------- |
| **Public**  | Yes (open source)                                 |
| **Private** | Only for team projects with external contributors |

### CODE_OF_CONDUCT.md

Only for public community projects. For personal repos: Not needed.

---

## What Does NOT Belong in Every Repo

| File               | Reason                                         |
| ------------------ | ---------------------------------------------- |
| docs/ folder       | README is usually enough, no separate doc site |
| SECURITY.md        | Only for public packages                       |
| Issue/PR Templates | Overkill for personal repos                    |

---

## Formatter by Language

| Language  | Formatter     | Config File      |
| --------- | ------------- | ---------------- |
| JS/TS     | Prettier      | `.prettierrc`    |
| Go        | gofmt         | - (built-in)     |
| Terraform | terraform fmt | - (built-in)     |
| Python    | Black/Ruff    | `pyproject.toml` |
| YAML      | Prettier      | `.prettierrc`    |

Only add when the language is used in the repo.

### Prettier Configuration (JS/TS)

**.prettierrc:**

See [templates/.prettierrc](https://github.com/sbaerlocher/sbaerlocher/tree/main/templates/.prettierrc)

**.prettierignore:**

See [templates/.prettierignore](https://github.com/sbaerlocher/sbaerlocher/tree/main/templates/.prettierignore)

**package.json Scripts:**

```json
{
  "scripts": {
    "format": "prettier --write .",
    "format:check": "prettier --check ."
  }
}
```

**Dependencies:**

```json
{
  "devDependencies": {
    "prettier": "^3.0.0",
    "prettier-plugin-astro": "^0.14.0",
    "prettier-plugin-svelte": "^3.0.0"
  }
}
```

Add plugins as needed per framework (astro, svelte, tailwind, etc.).

### YAML Linting

**Configuration**: `.yamllint.yml`

```yaml
extends: default

rules:
  line-length:
    max: 120
    level: warning
  indentation:
    spaces: 2
  comments:
    min-spaces-from-content: 1
```

**Usage**:

```bash
# Lint all YAML files
yamllint .

# Lint specific file
yamllint file.yaml

# Fix automatically (where possible)
yamllint --strict .
```

### Markdown Linting

**Configuration**: `.markdownlint.yml`

```yaml
# Extend default ruleset
default: true

# Line length
MD013:
  line_length: 120
  code_blocks: false
  tables: false

# Inline HTML
MD033: false

# Multiple headings with same content
MD024:
  siblings_only: true
```

**Usage**:

```bash
# Lint all markdown files
markdownlint '**/*.md'

# Lint specific file
markdownlint README.md

# Fix automatically
markdownlint --fix '**/*.md'
```

**Common Rules**:

- MD001: Heading levels increment by one
- MD013: Line length (120 characters)
- MD024: Multiple headings with same content
- MD025: Single title/H1 per document
- MD040: Fenced code blocks should have language

---

## Git Standards

### Commit Convention

**Format:** Conventional Commits with Claude Code signature

```text
<type>(<scope>): <subject>

<body>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Types:**

| Type       | Usage              | Description                                                      |
| ---------- | ------------------ | ---------------------------------------------------------------- |
| `feat`     | New features       | A new feature for the user                                       |
| `fix`      | Bug fixes          | A bug fix for the user                                           |
| `docs`     | Documentation      | Documentation only changes                                       |
| `style`    | Formatting         | Changes that don't affect code meaning (white-space, formatting) |
| `refactor` | Code restructuring | Code change that neither fixes a bug nor adds a feature          |
| `perf`     | Performance        | Code change that improves performance                            |
| `test`     | Tests              | Adding missing tests or correcting existing tests                |
| `chore`    | Maintenance        | Changes to build process, dependencies, tooling                  |
| `ci`       | CI/CD              | Changes to CI configuration files and scripts                    |

**Scopes:**

Project-specific, examples:

- `infrastructure/platform` - Platform provisioning
- `functions/github-stats` - GitHub Stats function
- `applications/authentik` - Authentik service

**Examples:**

```text
feat(functions): add GitHub SVG generator endpoint

Implemented new endpoint to generate SVG badges for GitHub stats.
Includes caching and error handling.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

```text
fix(infrastructure): correct CPU normalization for Fleet

Changed CPU limits from "1000m" to "1" format to prevent
Fleet Modified status.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Branch Strategy

**Main Branch:** `main` (preferred) or `master`

**Strategy by Project Type:**

| Project Type       | Strategy         | Description                                              |
| ------------------ | ---------------- | -------------------------------------------------------- |
| **GitOps**         | Direct to main   | No feature branches, all changes direct after validation |
| **Infrastructure** | Direct to main   | Fast deployment, CI/CD validation                        |
| **Applications**   | Feature branches | Use feature branches for complex changes                 |
| **Packages**       | Feature branches | Always use PRs for version-controlled releases           |

**Direct-to-Main Requirements:**

- CI/CD validation pipeline must pass
- Auto-rollback on failure (GitOps)

**Feature Branch Naming:**

```text
<type>/<short-description>

Examples:
- feat/user-authentication
- fix/memory-leak
- chore/update-dependencies
```

**Tags/Releases:**

- Semantic Versioning: `v1.2.3`
- Annotated tags: `git tag -a v1.2.3 -m "Release 1.2.3"`
- Packages: Automated via `release.yml` workflow

---

## GitHub Repository Configuration

All repositories must be configured consistently. Use the `gh` CLI or GitHub API to apply settings
programmatically.

### General Repository Settings

```bash
gh repo edit {owner}/{repo} \
  --delete-branch-on-merge \
  --enable-squash-merge \
  --enable-auto-merge

# gh repo edit has no --disable flags for merge types — use the API directly
gh api repos/{owner}/{repo} --method PATCH \
  --field allow_merge_commit=false \
  --field allow_rebase_merge=false
```

| Setting | Value | Reason |
| ----------------------- | ------------- | ---------------------------------------- |
| Delete branch on merge | Yes | Keeps branch list clean |
| Squash merge | Yes (default) | Clean, linear commit history |
| Merge commits | No | Squash preferred |
| Rebase merge | No | Squash preferred |
| Auto-merge | Enabled | Required for Renovate auto-merge to work |

**Exception:** GitOps/Infrastructure repos (`applications`, `infrastructure`) may prefer rebase merge
to preserve individual commit messages for auditability.

---

### GITHUB_TOKEN Default Permissions

**Set repository-level default to read-only.** Workflows must explicitly request write permissions.
This limits blast radius if a workflow is compromised.

```bash
gh api repos/{owner}/{repo} --method PATCH \
  --field default_workflow_permissions=read \
  --field can_approve_pull_request_reviews=false
```

Workflows that need write access declare it explicitly:

```yaml
permissions:
  contents: write      # only if needed (e.g. release)
  pull-requests: write # only if needed (e.g. claude-code-review)
```

**Anti-pattern (avoid):**

```yaml
# ❌ WRONG — grants full write to all resources
permissions: write-all
```

---

### Branch Protection — Repository Rulesets

Use **Repository Rulesets** (modern replacement for classic branch protection rules).

**Required rules for the `main` branch:**

| Rule | Setting | Reason |
| ------------------------------------ | ----------------------- | --------------------------------------- |
| Restrict deletions | Block | Protect main from accidental deletion |
| Block force pushes | Block | Protect commit history |
| Require pull request before merging | Yes | All changes via PR |
| Required approving reviews | 0 (personal) / 1 (team) | Flexible per project |
| Dismiss stale reviews on push | Yes (team repos) | Re-review after new commits |
| Require status checks to pass | Yes | CI must be green before merge |
| Require branches to be up to date | Yes | No merges on stale branches |

**Bypass actors:** By default no bypass list — admins are also bound by the ruleset. Add bypass
actors only when automation requires it (e.g. release bots), and document the reason.

**Configure via `gh` CLI (personal repo):**

```bash
gh api repos/{owner}/{repo}/rulesets --method POST --input - <<'EOF'
{
  "name": "main-branch-protection",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "ci" }
        ]
      }
    }
  ]
}
EOF
```

**For team repos** (set `required_approving_review_count: 1` and `dismiss_stale_reviews_on_push:
true`):

```json
{
  "type": "pull_request",
  "parameters": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews_on_push": true,
    "require_code_owner_review": true,
    "require_last_push_approval": false,
    "required_review_thread_resolution": true
  }
}
```

---

### Required Status Check Context Format

The `context` value must **exactly** match the string GitHub shows in the Check Suite. The format
depends on how the workflow is called:

| Workflow type | Context format | Example |
| -------------------- | ----------------------- | ----------------------- |
| Direct job | `<job-id>` | `ci` |
| Reusable workflow | `<caller-job> / <job>` | `ci / terraform` |
| Matrix job | `<job-id> (<matrix>)` | `ci (ubuntu-latest)` |

**Verify the exact string** by opening a PR and checking the "Checks" tab before adding it as a
required check.

**Required checks by repo type:**

| Repo Type | Required Checks |
| --------------------- | --------------- |
| Software / Packages | `ci` |
| Infrastructure (IaC) | `ci` |
| GitOps | `ci` |

**Never add as required checks:**

- `security` — runs on weekly schedule, would block all PRs
- `drift` — runs on weekly schedule, would block all PRs

---

### Full Setup Script

For consistent setup when creating a new repository:

```bash
#!/usr/bin/env bash
# Usage: ./scripts/setup-repo.sh <owner/repo>
set -euo pipefail

REPO=$1

# General settings
gh repo edit "$REPO" \
  --delete-branch-on-merge \
  --enable-squash-merge \
  --enable-auto-merge

gh api "repos/$REPO" --method PATCH \
  --field allow_merge_commit=false \
  --field allow_rebase_merge=false

# GITHUB_TOKEN: read-only by default
gh api "repos/$REPO" --method PATCH \
  --field default_workflow_permissions=read \
  --field can_approve_pull_request_reviews=false

# Branch ruleset
gh api "repos/$REPO/rulesets" --method POST --input - <<'EOF'
{
  "name": "main-branch-protection",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "ci" }
        ]
      }
    }
  ]
}
EOF
```

---

## Secret Management

**CRITICAL**: Secrets must NEVER be committed to Git.

### Prohibited Patterns

**NEVER commit**:

- `.env` files with secrets
- `credentials.json`
- API keys in code
- Terraform `.tfvars` with secrets
- Kubernetes secrets in YAML
- SSH keys, certificates
- Database passwords

### Approved Secret Storage

| Environment            | Method                    | Usage                         |
| ---------------------- | ------------------------- | ----------------------------- |
| **Kubernetes**         | External Secrets Operator | All K8s secrets via Bitwarden |
| **CI/CD**              | GitHub Repository Secrets | Workflow secrets              |
| **Cloudflare Workers** | Wrangler Secrets          | `wrangler secret put <NAME>`  |
| **Local Development**  | `.env.local` (gitignored) | Never committed               |

### External Secrets Operator Pattern

**For Kubernetes services**:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: service-credentials
  namespace: service
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: bitwarden-secretstore
    kind: ClusterSecretStore
  target:
    name: service-secret
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: <bitwarden-item-id>
        property: password
```

### Secret Naming Schema

**Standard across all repositories** (Bitwarden Secrets Manager):

```text
<Project> | <Service/Component> | <Verwendungsort/Scope> | <Permission> | <Type>
```

**Field Descriptions:**

- **Project**: Main project using this secret (e.g., `Functions`, `Infrastructure`, `Authentication`, `OpenArchiver`)
- **Service/Component**: External service or component (e.g., `GitHub API`, `Cloudflare DNS`, `Storj S3`)
- **Verwendungsort/Scope**: Where the secret is used (e.g., `nuvulus-cluster`, `sbaerlocher/functions`, `uptime-service`)
- **Permission**: Permission level (e.g., `read-only`, `read-write`, `admin`, `confidential`)
- **Type**: Credential type (e.g., `API Token`, `Access Key`, `Secret Key`, `Client Secret`)

**Important**: Not all fields are required for every secret. Field count is flexible, but order must be consistent.

**Examples:**

```text
# GitOps/Kubernetes
Infrastructure | Hetzner Cloud | nuvulus-cluster | read-write | API Token
Database | PostgreSQL | nuvulus-cluster | superuser | Password
OpenArchiver | Storj S3 | storage | read-write | Access Key

# Cloudflare Workers
Functions | Cloudflare Workers Deploy | sbaerlocher/functions | edit | API Token
Functions | GitHub API | sbaerlocher/functions repository | read-only | Personal Access Token
Functions | Grafana Synthetic Monitoring | uptime-service | read | API Token

# Terraform
Terraform | Cloudflare R2 | all-projects | read-write | Access Key ID
Authentication | Authentik API | terraform | admin | API Token
```

### Secret Scanning

**Automated Detection**:

- **CI/CD**: gitleaks action in workflows
- **GitHub**: Secret scanning alerts (public repos)

**gitleaks Configuration**:

See [templates/.gitleaks.toml](https://github.com/sbaerlocher/sbaerlocher/tree/main/templates/.gitleaks.toml)

### .gitignore for Secrets

**Required entries**:

```gitignore
# Secrets
.env
.env.local
.env.*.local
*.pem
*.key
*.crt
credentials.json
secrets.yaml
*-credentials.json

# Terraform
*.tfvars
!example.tfvars
terraform.tfstate
terraform.tfstate.backup

# Kubernetes
kubeconfig
*-secret.yaml
!*-secret.example.yaml
```

### Secret Rotation

**Regular rotation required for**:

- Database passwords (quarterly)
- API keys (semi-annually)
- Certificates (before expiry)
- Service account tokens (annually)

**Process**:

1. Generate new secret
2. Update in secret store (Bitwarden)
3. External Secrets refreshes automatically
4. Verify services still functional
5. Deactivate old secret

---

## AI Agent Documentation

AI instructions belong in a separate file, **not** in README.

**Recommended Structure:**

```text
repository/
├── AGENTS.md              # AI instructions (main file)
├── CLAUDE.md              # Only import: @AGENTS.md
├── .claude/
│   ├── commands/          # Custom Slash Commands (optional)
│   └── settings.local.json
└── README.md              # Human-readable docs
```

**CLAUDE.md Content (minimal):**

```markdown
@AGENTS.md
```

**AGENTS.md Content:**

- Project context for AI
- Code conventions
- Architecture overview
- Important patterns
- What AI should not do

**Why this approach?**

- AGENTS.md is the emerging standard (20,000+ repos)
- Claude Code currently only supports CLAUDE.md
- With `@AGENTS.md` import it works today
- Future-proof when AGENTS.md is officially supported

### .claude/commands/

Custom Slash Commands for recurring tasks.

**Standard Commands (all repos):**

| Command          | File               | Description                                                    |
| ---------------- | ------------------ | -------------------------------------------------------------- |
| `/code-review`   | `code-review.md`   | Code review for file/folder                                    |
| `/commit`        | `commit.md`        | Git commit with Conventional Commits                           |
| `/quality-check` | `quality-check.md` | All checks before PR                                           |
| `/actions-check` | `actions-check.md` | GitHub Actions best practices (SHA pinning, permissions, etc.) |

**Templates**: See [templates/commands/](https://github.com/sbaerlocher/sbaerlocher/tree/main/templates/commands/) for copy-paste examples.

**Project-specific Commands:**

| Repo Type          | Commands                          |
| ------------------ | --------------------------------- |
| Terraform          | `tf-plan.md`, `tf-apply.md`       |
| GitOps             | `fleet-check.md`, `helm-check.md` |
| Cloudflare Workers | `deploy.md`, `new-service.md`     |
| Packages           | `release.md`, `test.md`           |

**Format:**

```markdown
---
description: Short description for /help
---

Instructions for Claude...

$ARGUMENTS = Parameters from user
```

---

## Kubernetes Resource Standards

**For GitOps and Kubernetes projects**

### Resource Limits & Requests

**CRITICAL**: CPU values >= 1000m must use normalized string format

### Size Classes

Use standardized resource sizes:

| Size       | CPU Requests | CPU Limits | Memory Requests | Memory Limits |
| ---------- | ------------ | ---------- | --------------- | ------------- |
| **Micro**  | 50m          | 250m       | 64Mi            | 256Mi         |
| **Small**  | 100m         | 500m       | 128Mi           | 512Mi         |
| **Medium** | 200m         | "1"        | 256Mi           | 1Gi           |
| **Large**  | 500m         | "2"        | 512Mi           | 2Gi           |
| **XLarge** | "1"          | "4"        | 1Gi             | 4Gi           |

### CPU Normalization

**Why**: Kubernetes normalizes CPU values internally, causing Fleet "Modified" status

**Rules**:

```yaml
# ✅ CORRECT
resources:
  limits:
    cpu: "1"      # >= 1000m use string format
    cpu: "2"      # >= 1000m use string format
    memory: 2Gi
  requests:
    cpu: 500m     # < 1000m can use millicores
    memory: 512Mi

# ❌ WRONG
resources:
  limits:
    cpu: 1000m    # Will be normalized to "1" → Fleet drift!
    cpu: 2000m    # Will be normalized to "2" → Fleet drift!
```

### Deployment Strategies

**Resource-Constrained Clusters** (CPU >95%):

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 0 # No extra pods during update
      maxUnavailable: 1 # Old pod terminated first
```

**Standard Clusters** (CPU <90%):

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1 # One extra pod during update
      maxUnavailable: 0 # Zero downtime
```

### Service Assignments

**By Service Type**:

- **Large**: Databases (PostgreSQL), Ingress (Traefik)
- **Medium**: External Secrets, Monitoring, Authentik, n8n
- **Small**: Cert-Manager, Operators, External-DNS
- **Micro**: Reflector, lightweight operators

### Health Checks

**Required for all services**:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 3
```

---

## Monitoring Standards

**For services with metrics**

### Grafana Alloy Annotations

**Required for Prometheus scraping**:

```yaml
metadata:
  annotations:
    k8s.grafana.com/scrape: 'true'
    k8s.grafana.com/metrics.portNumber: '9187'
    k8s.grafana.com/metrics.path: '/metrics'
    k8s.grafana.com/job: '<service-name>'
    k8s.grafana.com/metrics.scrapeInterval: '60s' # Optional
```

### Common Metrics Ports

| Service               | Port  | Path     | Key Metrics                            |
| --------------------- | ----- | -------- | -------------------------------------- |
| **External Secrets**  | 8080  | /metrics | `externalsecret_status_condition`      |
| **Cert-Manager**      | 9402  | /metrics | `certmanager_certificate_ready_status` |
| **PostgreSQL (CNPG)** | 9187  | /metrics | `cnpg_pg_database_size_bytes`          |
| **Traefik**           | 9100  | /metrics | `traefik_service_requests_total`       |
| **Alloy**             | 12345 | /metrics | `prometheus_target_scrapes_total`      |

### Metrics Naming Convention

**Format**: `<namespace>_<resource>_<metric>_<unit>`

**Examples**:

- `http_requests_total` (counter)
- `http_request_duration_seconds` (histogram)
- `database_connections_active` (gauge)
- `cache_hits_total` (counter)

### Alert Thresholds

**Standard SLOs**:

- **Availability**: 99.9% (max 43.8 min downtime/month)
- **Latency (p95)**: < 500ms
- **Error Rate**: < 1%
- **Saturation**: < 80% CPU/Memory

---

## Template for New Repos

```text
new-repo/
├── .github/
│   ├── CODEOWNERS
│   └── renovate.json
├── AGENTS.md
├── CLAUDE.md
├── .editorconfig
├── .gitignore
├── LICENSE                    # public repos only
├── README.md
└── [project files]
```

**CLAUDE.md:**

```markdown
@AGENTS.md
```

**AGENTS.md:**

```markdown
# Project Name

## Context

[What the project does, for AI]

## Conventions

[Code style, patterns]

## Structure

[Important folders/files]
```

**README.md:**

```markdown
# project-name

What the project does (1 sentence).

## Setup

\`\`\`bash

# Installation/start commands

\`\`\`

## License

MIT
```

---

## Summary

**Principles:**

1. Less is more
2. README is the main documentation
3. LICENSE always included
4. CHANGELOG only for releases
5. Workflows only what's needed
6. No template files that stay empty

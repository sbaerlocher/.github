# Repository Standards

## Principles

| Aspect              | Public            | Private                  |
| ------------------- | ----------------- | ------------------------ |
| `LICENSE`           | MIT (Required)    | None (rights with owner) |
| `security.yml`      | Required (CodeQL) | Optional                 |
| Claude AI workflows | Not recommended   | Recommended              |
| All other structure | Identical         | Identical                |

---

## Required Files (Every Repo)

| File                    | Notes                                  |
| ----------------------- | -------------------------------------- |
| `AGENTS.md`             | AI instructions (main file)            |
| `CLAUDE.md`             | Only: `@AGENTS.md`                     |
| `README.md`             | 1-2 sentences + quick start            |
| `REVIEW.md`             | Code review guidelines                 |
| `.editorconfig`         | See templates repo                     |
| `.gitignore`            | Minimal — build outputs, deps, IDE, OS |
| `.github/CODEOWNERS`    | `* @sbaerlocher`                       |
| `.github/renovate.json` | Extend shared preset (see below)       |
| `LICENSE`               | MIT — public repos only                |

### README.md

Minimal: name, 1-2 sentence description, quick start commands. No badges, no long feature lists.

### REVIEW.md

Documents review scope, required checks, severity levels, and which PRs to skip.
See [REVIEW.md](./REVIEW.md) in this repository as a reference implementation.

Minimal template:

```markdown
# Code Review Guidelines

## Scope

[What is in / out of scope for reviews in this repo]

## Required checks

[Repo-specific checks reviewers must verify]

## Severity levels

| Level        | Meaning                                             | Merge impact       |
| ------------ | --------------------------------------------------- | ------------------ |
| Bug          | Incorrect behavior or broken contract               | Blocks merge       |
| Nit          | Minor issue — suboptimal but not incorrect          | Non-blocking       |
| Pre-existing | Issue present before this PR; flagged for awareness | No action required |

## Skip

[PR types that do not require a full review]
```

### AGENTS.md

Project context for AI agents: what the project does, code conventions, architecture, important
patterns, what AI should not do. See workspace `AGENTS.md` for full guidance.

`CLAUDE.md` contains only: `@AGENTS.md`

---

## Optional Files

| File                 | When                                           |
| -------------------- | ---------------------------------------------- |
| `CHANGELOG.md`       | Packages / repos with versioned releases only  |
| `ARCHITECTURE.md`    | Infrastructure, monorepos                      |
| `OPERATIONS.md`      | Production services with runbooks              |
| `DEPLOYMENT.md`      | Complex deploy processes (more than 1 command) |
| `.github/SECRETS.md` | Any repo that uses secrets                     |
| `CONTRIBUTING.md`    | Public repos only                              |

Files that do NOT belong in every repo: `docs/`, `SECURITY.md`, issue/PR templates,
`CODE_OF_CONDUCT.md` (only for public community projects).

---

## Workflows

All reusable workflows live in `sbaerlocher/.github/.github/workflows/`. Reference with a
date-based version tag for reproducibility:

```yaml
uses: sbaerlocher/.github/.github/workflows/ci-terraform.yml@2026-02-14
```

### Required Workflows by Repo Type

| Repo Type             | Required                                  | Optional                |
| --------------------- | ----------------------------------------- | ----------------------- |
| Software / Packages   | `ci.yml`, `release.yml`                   | `security.yml`          |
| Infrastructure (IaC)  | `ci.yml`, `deploy.yml`, `security.yml`    | `drift.yml`, `docs.yml` |
| GitOps                | `ci.yml`, `deploy.yml`                    | —                       |
| Serverless            | `ci.yml`, `deploy.yml`                    | —                       |
| **All public repos**  | + `security.yml` (CodeQL)                 | —                       |
| **All private repos** | + `ai-claude.yml`, `ai-claude-review.yml` | —                       |

### Available Reusable Workflows

| Category | File                              | Description                        |
| -------- | --------------------------------- | ---------------------------------- |
| CI       | `ci-go.yml`                       | Go tests, linting                  |
| CI       | `ci-js.yml`                       | JS/TS quality, tests, security     |
| CI       | `ci-terraform.yml`                | TF validate, fmt, tflint           |
| CI       | `ci-gitops.yml`                   | Fleet & K8s validation             |
| CI       | `ci-ansible.yml`                  | Ansible syntax & lint              |
| Deploy   | `deploy-terraform.yml`            | Terraform plan & apply             |
| Deploy   | `deploy-cloudflare-workers.yml`   | Wrangler deploy                    |
| Release  | `release-go.yml`                  | GoReleaser (multi-platform)        |
| Release  | `release-docker.yml`              | Docker build & push                |
| Release  | `release-helm.yml`                | Helm chart publish (OCI)           |
| Release  | `release-npm.yml`                 | NPM publish with provenance        |
| Security | `security-code.yml`               | CodeQL SAST (multi-language)       |
| Security | `security-config.yml`             | Terraform / K8s / Ansible          |
| Security | `security-deps.yml`               | Go, JS/TS, Python dependencies     |
| Security | `security-secrets.yml`            | Gitleaks, TruffleHog               |
| Security | `security-containers.yml`         | Trivy, Grype                       |
| Security | `security-sbom.yml`               | SBOM & Cosign signing              |
| Ops      | `ops-terraform-orchestration.yml` | Multi-environment TF               |
| AI       | `ai-claude-review.yml`            | Auto code review (reads REVIEW.md) |
| AI       | `ai-claude.yml`                   | On-demand @claude mentions         |
| E2E      | `e2e-docker.yml`                  | E2E tests via Docker Compose       |

### Action SHA Pinning

All `uses:` references must be pinned to a full 40-character commit SHA with the version tag
as an inline comment:

```yaml
# Correct
uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4.1.1

# Wrong
uses: actions/checkout@v4
```

Renovate updates SHA references automatically when `pinDigests: true` is set.

### Workflow Trigger Pattern (No Duplicate Runs)

```yaml
# ci.yml — on PR only, and when called by other workflows
on:
  pull_request:
    branches: [main]
  workflow_call:

# deploy.yml — on push to main, calls ci.yml internally
on:
  push:
    branches: [main]
  workflow_dispatch:
```

This ensures CI runs once on PR and once on merge (as part of deploy) — not twice on main.

### Scheduled Workflows

Run weekly, not daily: `cron: '0 6 * * 1'` (Monday 06:00 UTC).

Never add `security.yml` or `drift.yml` as required status checks — they run on schedule,
not on PRs, and would block every merge.

### AI Workflows (Private Repos Only)

- `ai-claude-review.yml`: Automatic code review on PRs — reads `REVIEW.md` as context
- `ai-claude.yml`: On-demand via `@claude` mentions in issues/PRs
- Required secret: `CLAUDE_CODE_OAUTH_TOKEN` (from Anthropic Console)

---

## Renovate

Shared presets in `sbaerlocher/.github`. Each repo extends exactly one:

| Repo type       | Preset               |
| --------------- | -------------------- |
| JS/TS           | `renovate-js`        |
| Terraform/IaC   | `renovate-terraform` |
| GitOps/Helm     | `renovate-gitops`    |
| Everything else | `renovate-base`      |

```json
{ "extends": ["github>sbaerlocher/.github:renovate/renovate-base"] }
```

Project-specific rules go in `packageRules` — never duplicate base config inline.

---

## Git Standards

### Commit Format

```text
<type>(<scope>): <subject>

<body>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `ci`

Scopes are project-specific, e.g. `infrastructure/platform`, `functions/github-stats`.

### Branch Strategy

| Repo Type              | Strategy                      |
| ---------------------- | ----------------------------- |
| GitOps, Infrastructure | Direct to main (CI must pass) |
| Applications, Packages | Feature branches + PRs        |

Feature branch format: `<type>/<short-description>` (e.g. `feat/user-auth`)

Tags: semantic versioning `v1.2.3`, annotated (`git tag -a v1.2.3 -m "Release 1.2.3"`).

---

## GitHub Repository Settings

| Setting                | Value         | Reason                                             |
| ---------------------- | ------------- | -------------------------------------------------- |
| Squash merge           | Yes (default) | Clean, linear commit history                       |
| Merge commits          | No            | Squash preferred                                   |
| Rebase merge           | No            | Squash preferred                                   |
| Delete branch on merge | Yes           | Keeps branch list clean                            |
| Auto-merge             | Enabled       | Required for Renovate auto-merge                   |
| GITHUB_TOKEN default   | Read-only     | Workflows declare write permissions explicitly     |
| Required status check  | `ci`          | Only if repo has `pull_request`-triggered workflow |

See [SETUP.md](./SETUP.md) for the full setup script and branch ruleset commands.

---

## Secret Management

**Never commit**: `.env` files, credentials, API keys, `.tfvars` with secrets, SSH keys,
Kubernetes secrets in YAML.

| Environment        | Method                                     |
| ------------------ | ------------------------------------------ |
| Kubernetes         | External Secrets Operator + Bitwarden      |
| CI/CD              | GitHub Repository Secrets                  |
| Cloudflare Workers | `wrangler secret put <NAME>`               |
| Local dev          | `.env.local` (gitignored, never committed) |

Secret naming: `<Project> | <Service> | <Scope> | <Permission> | <Type>`

---

## Code Quality

| Language  | Formatter     | Linter        | Config           |
| --------- | ------------- | ------------- | ---------------- |
| JS/TS     | Prettier      | ESLint        | `.prettierrc`    |
| Go        | gofmt         | golangci-lint | —                |
| Terraform | terraform fmt | tflint        | —                |
| Python    | Black/Ruff    | Ruff          | `pyproject.toml` |
| YAML      | Prettier      | yamllint      | `.yamllint.yml`  |

Line length: 120 characters. Only add formatter config when the language is used in the repo.

See [templates](https://github.com/sbaerlocher/sbaerlocher/tree/main/templates/) for
`.prettierrc`, `.editorconfig`, `.yamllint.yml`, `.markdownlint.yml`, and `.gitleaks.toml`.

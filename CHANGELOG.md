# Changelog

All notable changes to this project will be documented in this file.

This is a rolling release - changes are deployed continuously to `main`.

---

## 2026-03-21

### Changed

- **ci-go.yml**: Add `MPL-2.0` to allowed licenses in dependency review
  - Aligns Go CI allowlist with JS CI (`ci-js.yml` already permits MPL-2.0)
  - Required by `lightningcss@1.32.0` (transitive dependency of Vite v8)

---

## 2026-03-20

### Changed

- **GitHub Actions**: Update action SHA digests (#23, #24)
  - `github/codeql-action` SHA → `c6f9311` (#23): ci-go.yml, ci-js.yml, ci-terraform.yml, release-docker.yml,
    security-code.yml, security-config.yml, security-containers.yml
  - `codecov/codecov-action` v5.5.2 → v5.5.3 (#24): ci-go.yml, ci-js.yml
  - `actions/cache` v5.0.3 → v5.0.4 (#24): ci-js.yml, deploy-cloudflare-workers.yml, deploy-terraform.yml
  - `trufflesecurity/trufflehog` v3.93.8 → v3.94.0 (#24): security-secrets.yml
- **renovate-base.json**: Refine scheduling and automerge behavior
  - Schedule changed from `"before 6am on Monday"` to `"before 6am"` (daily)
  - Remove `prCreation: "not-pending"` to allow immediate PR creation
  - Remove `internalChecksFilter: "strict"` to not block automerge on internal checks
  - Fix `sbaerlocher/.github` package rule: replace deprecated `matchPackageNames` with `matchDepNames`
  - Set `minimumReleaseAge: "1 days"` for `.github` preset references (was `"0 days"`)
  - Remove generic `_VERSION` Makefile custom manager (covered by ecosystem-specific presets)
- **renovate-docker.json**: Improve stability and image matching
  - Add `minimumReleaseAge: "5 days"` to Base OS, language runtime, and web server image rules
  - Add `/^go$/` to language runtime image patterns
  - Fix Docker image regex: require tag (prevent digest-only false matches)
- **renovate-go.json**: Consolidate package groups
  - Merge 7 separate groups into 3: "Go ecosystem packages", "Go platform packages", "Go dev tooling"
  - Remove "Go indirect dependencies" explicit rule
- **renovate-js.json**: Add priority ordering and consolidate groups
  - Add `prPriority: 20` for Node.js, `prPriority: 5` for TypeScript and pnpm
  - Merge ESLint + Prettier into "Code quality tools"
  - Merge Vitest + Jest into "Testing tools"
  - Increase major build tooling `minimumReleaseAge` from `"10 days"` to `"14 days"`
- **renovate-kubernetes.json**: Improve regex and priority assignment
  - Move `prPriority: 5` from Helm charts to critical platform charts
  - Fix Fleet HTTP regex to prevent cross-matches between multiple `repo:`/`chart:`/`version:` blocks
  - Add `currentDigest` capture group to Docker image regex for digest tracking
  - Improve description for custom regex `pinDigests: false` rule
- **renovate-terraform.json**: Remove Terragrunt support
  - Remove `terragrunt` and `terragrunt-version` managers
  - Remove Terragrunt version rules and custom managers
  - Remove pre-commit terraform hooks rule
  - Add `prPriority: 5` to critical providers
  - Simplify Makefile custom manager to Terraform only

---

## 2026-03-19

### Changed

- **GitHub Actions**: Update SHA-pinned action references across workflows (#21, #22)
  - `pnpm/action-setup` v4.4.0 → v5.0.0 (ci-js.yml, deploy-cloudflare-workers.yml, e2e-docker.yml,
    quality-benchmarks.yml, release-npm.yml, security-code.yml, security-deps.yml)
  - `anthropics/claude-code-action` SHA update to latest v1 (ai-claude.yml, ai-claude-review.yml)
  - `actions/cache` SHA update to latest v5 (release-go.yml)

---

## 2026-03-16

### Changed

- **renovate-*.json**: Migrate deprecated options and simplify all 6 presets (#15)
  - `stabilityDays` → `minimumReleaseAge` (26 occurrences across all presets)
  - `matchPackagePrefixes` → `matchPackageNames` with glob syntax (renovate-go.json)
  - `matchPackagePatterns` → `matchPackageNames` with regex syntax (renovate-js.json, renovate-docker.json)
  - `fileMatch` → `managerFilePatterns` (renovate-terraform.json, renovate-kubernetes.json, renovate-docker.json, renovate-go.json)
  - `regexManagers` → `customManagers` with `customType: "regex"` (renovate-kubernetes.json)
  - Remove `dependencyDashboardApproval` to allow automatic PR creation
  - Remove redundant rules already inherited from `renovate-base.json`
  - Add `configMigration: true` to base for automatic future migration PRs
- **GitHub Actions**: Update SHA-pinned action references across workflows (#16, #17, #18, #19, #20)
  - `actions/cache` v4 → v5
  - `slackapi/slack-github-action` v2 → v3
  - `postgres` Docker tag v17 → v18
  - Various actions updated to latest SHA (actions/checkout, actions/setup-node, actions/setup-go, github/codeql-action, anthropics/claude-code-action, aquasecurity/trivy-action, anchore/sbom-action, sigstore/cosign-installer, docker/build-push-action, docker/metadata-action)

### Fixed

- **ci-go.yml**: Allow compound SPDX license `BSD-3-Clause AND LicenseRef-scancode-google-patent-license-golang` in dependency review (#14)

---

## 2026-03-15

### Changed

- **ai-claude-review.yml**: Switch to official code-review plugin with inline comments (#13)
  - Migrate from manual `gh pr comment` review to `code-review@claude-code-plugins` plugin
  - Add `plugin_marketplaces` pointing to `anthropics/claude-code.git`
  - Enable `pull-requests: write` permission for inline review comments
  - Use `/code-review --comment` prompt for structured inline PR reviews
  - Add `fetch-depth: 1` for faster checkout

---

## 2026-03-08

### Changed

- **release-go.yml**: Add Go build caching for faster releases
  - Enable module cache via `setup-go` (`cache: true`)
  - Add separate `actions/cache` step for Go build artifacts (`~/.cache/go-build`)
  - Cache key based on `go.sum` hash with fallback restore keys

---

## 2026-03-07

### Changed

- **ci-go.yml**: Split `test-and-lint` job into separate postgres and non-postgres variants
  - New `test-and-lint` job runs when `enable-postgres` is `false` (default)
  - New `test-and-lint-postgres` job runs when `enable-postgres` is `true`, with dedicated PostgreSQL service container
  - Removes conditional service container pattern (empty strings for disabled services)
  - Coverage output merges both job variants via `||` fallback
  - `security-scan` and `codeql-analysis` jobs now depend on both variants with `always()` and failure/cancellation guards
- **renovate-base.json**: Enable automerge for own workflow and preset updates
  - Add `automerge: true` and `stabilityDays: 0` to `sbaerlocher/.github` workflow package rule
  - New package rule for `sbaerlocher/.github` Renovate preset references with automerge enabled
  - Ensures own workflow and preset version bumps are merged automatically without delay

### Documentation

- **release.md**: Update release process to include `latest` tag management

---

## 2026-03-06

### Changed

- **GitHub Actions**: Update SHA-pinned action references across 18 workflows (#5, #6, #7, #8, #9, #10, #11, #12)
  - `actions/upload-artifact` v6.0.0 → v7.0.0
  - `actions/download-artifact` v7 → v8
  - `actions/setup-node` v6.2.0 → v6.3.0
  - `actions/dependency-review-action` v4.8.3 → v4.9.0
  - `hashicorp/setup-terraform` v3.1.2 → v4.0.0
  - `docker/build-push-action` v6 → v7
  - `docker/metadata-action` v5 → v6
  - `docker/login-action` v3 → v4
  - `docker/setup-buildx-action` v3 → v4
  - `docker/setup-qemu-action` v3 → v4
  - `oven-sh/setup-bun` v2.1.2 → v2.1.3
  - `dominikh/staticcheck-action` v1.4.0 → v1.4.1
  - `github/codeql-action` updated to latest SHA (v4)
  - `anthropics/claude-code-action` updated to latest SHA (v1)
  - `bitwarden/sm-action` updated to latest SHA (v2)
  - `aquasecurity/trivy-action` updated to latest SHA
  - `trufflesecurity/trufflehog` updated to latest SHA (v3)
  - `sigstore/cosign-installer` updated to latest SHA (v3)
  - `anchore/sbom-action` updated to latest SHA (v0)

---

## 2026-03-05

### Changed

- **GitHub Actions**: Update SHA-pinned action references across 15 workflows (#4)
  - `actions/setup-go` v6.2.0 → v6.3.0
  - `actions/dependency-review-action` v4.8.2 → v4.8.3
  - `aquasecurity/trivy-action` 0.34.0 → 0.34.2
  - `github/codeql-action` updated to latest SHA (v4)
  - `anthropics/claude-code-action` updated to latest SHA (v1)
  - `actions/setup-node` updated to latest SHA (v4)
  - `sigstore/cosign-installer` updated to latest SHA (v3)
  - `anchore/sbom-action` updated to latest SHA (v0)

---

## 2026-02-25

### Fixed

- **ops-drift-detection.yml**: Align inputs with deploy-terraform workflow
  - Add `should-apply: false` to explicitly prevent apply during drift detection
  - Remove unsupported `create-drift-issue` input
- **deploy-terraform.yml**: Fix apply condition to require both deploy mode and approval
  - Changed from `OR` (`||`) to `AND` (`&&`) for `mode == 'deploy'` and `should-apply == 'true'`
  - Prevents unintended applies when `should-apply` is not explicitly set

---

## 2026-02-24

### Changed

- **renovate-base.json**: Skip stability days for own workflow tags
  - Set `minimumReleaseAge: 0 days` for `sbaerlocher/.github` package rule
  - Prevents Renovate from holding back new date tags due to global `stabilityDays: 3`

### Fixed

- **ops-drift-detection.yml**: Fix incorrect workflow reference
  - Changed `terraform-deploy.yml` → `deploy-terraform.yml` to match actual file name

---

## 2026-02-23

### Changed

- **security-code.yml**: Add multi-package-manager support for JavaScript/TypeScript CodeQL analysis
  - New `package-manager` input to override auto-detection (npm, pnpm, yarn)
  - Auto-detects package manager from lock files (`pnpm-lock.yaml`, `yarn.lock`, fallback to npm)
  - Installs pnpm via `pnpm/action-setup` when needed
  - Separate install steps per package manager with proper frozen lockfile flags
  - Build step uses detected package manager instead of hardcoded `npm`
  - Node.js setup caches correct package manager dependencies
  - Summary report includes detected package manager
- **security-code.yml**: Add configurable SARIF upload toggle
  - New `enable-sarif-upload` boolean input (default: `true`)
  - When disabled, SARIF results are uploaded as workflow artifacts (30-day retention)
  - Single CodeQL analyze step with conditional `upload` parameter
  - Enables CodeQL analysis for private repos without GitHub Advanced Security
  - Summary report reflects the chosen upload mode
- **renovate-base.json**: Add date-based versioning for reusable workflow references
  - Regex versioning maps `YYYY-MM-DD` tags to semver comparison (`major.minor.patch`)
  - `allowedVersions` filter excludes non-date tags (e.g. `latest`)
  - Enables Renovate to detect and update `@2026-02-14` → `@2026-02-23` workflow references
- **renovate-base.json**: Add custom regex manager for pinned Renovate preset versions
  - Detects `github>sbaerlocher/.github:preset#YYYY-MM-DD` references in Renovate configs
  - Uses `github-tags` datasource to look up available date tags
  - Enables automatic PRs when new preset versions are tagged
  - Matches `renovate*.json`, `.renovaterc.json`, and `.renovaterc` files

---

## 2026-02-21

### Added

- **security-sbom.yml**: New dedicated workflow for SBOM generation without signing capabilities
  - Supports all artifact types: container, filesystem, go-binary, npm-package
  - Minimal permissions: only `contents: write` required
  - Lightweight alternative to `security-supply-chain.yml` for non-container artifacts
  - Includes SBOM validation and artifact upload
  - Generates summary report with component count and usage instructions

### Changed

- **release-npm.yml**: Improved package verification with retry logic
  - Added exponential backoff retry mechanism (6 attempts, max ~3 minutes)
  - Starts with 5s wait, doubles each attempt (5s, 10s, 20s, 40s, 80s, 160s)
  - Prevents false failures when NPM registry is slow to update
  - Better error messages indicating registry propagation delay
  - Resolves intermittent verification failures after successful publish

### Fixed

- **release-npm.yml**: Fixed bash syntax errors in publish steps
  - Use environment variable `CUSTOM_PUBLISH_CMD` instead of direct template expansion
  - Prevents empty else blocks when `publish-command` input is not provided
  - Changed from `${{ inputs.publish-command }}` to `$CUSTOM_PUBLISH_CMD` variable
  - Environment variable ensures else block always contains a valid command
  - Applies to both "Publish to NPM" and "Publish to NPM (Dry Run)" steps
  - Fixes: "syntax error near unexpected token 'else'" and "syntax error near unexpected token 'fi'"
- **release-npm.yml**: Use dedicated `security-sbom.yml` workflow instead of `security-supply-chain.yml`
  - Resolves permission conflict where `security-supply-chain.yml` required `packages: write` for container signing
  - Now uses SBOM-only workflow that doesn't require container registry permissions
  - Fixes workflow validation error: "The nested job 'sign-container' is requesting 'packages: write'"
- **security-supply-chain.yml**: Moved `packages: write` permission from workflow-level to job-level
  - `packages: write` is now only granted to the `sign-container` job
  - Workflow-level permissions reduced to `contents: write` and `id-token: write`
  - Maintains full functionality for container image signing and SBOM attachment

---

## 2026-02-16

### Changed

- **renovate-base.json**: Disable digest pinning for reusable workflows from `sbaerlocher/.github`
  - Reusable workflows now use version tags (e.g., `@v1`) instead of SHA pinning
  - Third-party actions remain SHA-pinned for supply-chain security
  - New `packageRule` matching `sbaerlocher/.github` with `pinDigests: false`
- **renovate-kubernetes.json**: Add `registryUrlTemplate` for OCI Helm chart detection
  - Fixes registry URL resolution for custom OCI chart repositories
- **ai-claude-review.yml**: Remove concurrency group from Claude code review workflow
  - Prevents cancellation of in-progress reviews when new commits are pushed
- **renovate-kubernetes.json**: Disable digest pinning for Fleet/Helm values custom regex manager
  - Prevents SHA pinning for OCI Helm charts detected via custom regex

---

## 2026-02-14

### Added

- **AGENTS.md** - Comprehensive AI agent documentation for workflow repository
- **CLAUDE.md** - Import reference for Claude Code integration
- **LICENSE** - MIT license for public repository
- **.editorconfig** - Editor consistency configuration across all files
- **.gitignore** - Ignore patterns for secrets, temp files, and local settings
- **.github/CODEOWNERS** - Repository ownership and review requirements
- **.github/renovate.json** - Renovate configuration extending base preset
- **README.md**: Complete documentation for all 27 workflows
  - New "Testing & Quality" category (3 workflows)
  - Full documentation for previously undocumented workflows:
    - `e2e-docker.yml` - E2E Testing with Docker Compose
    - `helm-test.yml` - Helm Chart Testing with Kind
    - `quality-benchmarks.yml` - Performance Benchmarking
    - `notify-deployment.yml` - Deployment Notifications

### Changed

- **README.md**:
  - Updated workflow count: 24 → 27
  - Updated workflow statistics and categories
  - Fixed references: CHANGES.md → CHANGELOG.md
  - Updated to rolling release model
- **CHANGELOG.md**: Renamed from CHANGES.md, switched to rolling release format
- **release-go.yml**:
  - Added `extra-env` input for additional environment variables (multiline KEY=VALUE format)
  - Security improvement: Environment variables now passed via `env:` block to prevent command injection
  - Enables custom environment variables for GoReleaser builds (e.g., CGO_ENABLED, GOOS)
- **ci-terraform.yml** & **security-config.yml**:
  - Migrated from abandoned `aquasecurity/tfsec-action` to `aquasecurity/trivy-action@0.33.1`
  - TFSec was deprecated and integrated into Trivy by Aqua Security
  - Updated artifact names: `tfsec-results` → `trivy-terraform-results`
  - Updated SARIF category: `tfsec` → `trivy-terraform`
  - Improved Terraform security scanning with latest tooling

### Repository Status

✅ Fully compliant with [STANDARDS.md](./STANDARDS.md)
✅ All required files for public repository present
✅ All 27 workflows documented
✅ AI-ready with comprehensive AGENTS.md

---

## 2026-01-29

### Added

Initial deployment of consolidated reusable workflows:

- **CI workflows**: Go, JavaScript/TypeScript, Terraform
- **Security workflows**: CodeQL, Config scanning, Dependencies, Secrets, Containers, Supply chain
- **Deploy workflows**: Terraform, Cloudflare Workers
- **Release workflows**: Go, Docker, Helm, NPM
- **Operations workflows**: Drift detection, Secret sync, Orchestration

### Summary

24 consolidated workflows deployed, reducing complexity by 33% while increasing feature coverage by 100%.

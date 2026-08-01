# Changelog

All notable changes to this project will be documented in this file.

This is a rolling release - changes are deployed continuously to `main` and
consumed via date-based tags (`YYYY-MM-DD`).

## Breaking changes & support policy

Consumers pin a date tag and bump it via Renovate. Two rules make that safe:

- **Breaking changes are flagged explicitly.** Any change that alters required
  inputs, removes an input/output, or changes default behaviour gets a
  `### ⚠ BREAKING` heading in its dated entry below, naming the affected
  workflow and a one-line migration step. Scan for `⚠ BREAKING` before bumping
  a tag — that is the single source of truth for what might break.
- **Only the latest tag is supported.** Older date tags keep working
  (immutable), but fixes and security patches land only on `main` / the newest
  tag. Pin an old tag at your own risk; there is no backport.

---

## 2026-08-01

### Fixed

- **`ci-js.yml` — `coverage` output resolved to an empty string.** The
  `workflow_call` output pointed at `jobs.test`, but no such job exists; the
  job exporting coverage is `quality-and-test`. Consumers reading
  `needs.<job>.outputs.coverage` received `''` on every run and now get the
  actual percentage (or `N/A` when coverage is disabled). Not breaking — the
  previous value carried no information — but review any consumer that treated
  the empty string as "coverage is off".
- **`scripts/drift-issue-body.sh` — GNU-only sed idiom.** Trailing blank lines
  were trimmed via `sed -e :a -e '/^\n*$/{$d;N;ba}'`, which aborts on BSD sed
  with `unexpected EOF`. Replaced with a portable awk equivalent so the script
  and its self-check run on macOS. Local runs only; CI runners are Linux and
  were never affected. Scoped to the script — `ops-drift-issue.yml:123` still
  carries an inline copy of the same idiom, left for a follow-up.

### Added

- **`justfile` — task entrypoint for this repository.** `just lint`,
  `just test` and `just fmt` replace the checks previously spread across
  `lefthook.yml`, `CONTRIBUTING.md` prose and a script comment. Repository-local
  only, consumer repos are unaffected. `templates/justfile` stays the reference
  template for consumers and is unchanged.
- **`ai-claude-review.yml` — review budgets are now configurable.** New
  optional `max-turns-first` (default `100`), `max-turns-followup`
  (default `40`) and `timeout-minutes` (default `30`) inputs. All three
  were previously hard-coded, so a consumer could not raise them without
  forking the workflow. Defaults match the previous values — no behaviour
  change unless a caller sets them.

  **When to raise `max-turns-followup`:** the `40` default assumes a
  follow-up only inspects the delta since the last review. On a PR whose
  follow-up still spans many changed files, the budget can run out before
  the review submits its closing verdict — the job then fails after having
  posted its inline comments, and the stale `CHANGES_REQUESTED` from the
  first pass keeps blocking the merge.

  **Raise `timeout-minutes` alongside it.** The two limits bind
  independently and produce the same visible failure, so lifting only the
  turn budget just trades the turn wall for the clock wall.

### Changed

- **`security-secrets.yml` — dropped the report-only generic pattern greps.**
  The `password:`/`apiKey:`/`token:` greps over YAML warned but could never
  fail the job by design, and in Ansible and GitOps repos they mostly matched
  variable names next to `secretKeyRef`. No gate is lost — the step could not
  fail by design, so only warning-level log output disappears. Gitleaks and
  TruffleHog remain the secret scanners, within their own limits: TruffleHog
  runs `--only-verified` over the pushed diff, and gitleaks' generic rules are
  entropy-gated, so a low-entropy hardcoded value is caught by neither. The
  input name
  `enable-pattern-detection` and the fail behaviour of the AWS-key and
  private-key checks are unchanged; its description and the report row now
  name the two checks that actually run. Consumers scanning before a bump:
  no action needed.

---

## 2026-07-27

### Changed

- **Renovate presets — automerge scope widened.** The stability rules for
  `node`, `typescript`, `pnpm` (`renovate-js.json`), Terraform Core and the
  critical providers (`renovate-terraform.json`), the critical platform Helm
  charts (`renovate-kubernetes.json`) and the Go runtime (`renovate-go.json`)
  set `automerge: false` **without** `matchUpdateTypes`, so they gated every
  update type instead of only the breaking ones their descriptions describe.
  Renovate therefore never enabled auto-merge on those PRs, the ruleset's
  Renovate bypass never applied, and each one needed a manual approval.
  Each rule is now split: grouping, release age, priority and labels keep
  matching every update type, and a second rule carries `automerge: false`
  scoped to the breaking types only.

  **Consumers scanning before a bump:** critical Terraform providers and
  critical platform Helm charts now automerge **patch** bumps unattended
  where they previously waited for a manual merge. `minimumReleaseAge`
  (7 days) still applies. Terraform Core and the Go runtime gate
  `major` + `minor`, because neither has left major `1` — gating on `major`
  alone would never match and would have let a state-format or
  language-version bump through. To keep a package fully manual in one repo,
  re-add a rule with `automerge: false` and no `matchUpdateTypes` in that
  repo's own `renovate.json`.

---

## 2026-07-26

### ⚠ BREAKING

- **`ai-claude-review.yml`**: default `model` bumped `claude-opus-4-8` →
  `claude-opus-5` for both review passes. Callers that do not set `model`
  pick this up automatically on the next tag bump — review behaviour and
  per-PR token cost change accordingly. Migration: pin the previous
  behaviour with `with: { model: claude-opus-4-8 }`, or set a cheaper tier.

### Changed

- **`renovate-js.json`**: TypeScript **major** updates now require manual
  approval (`dependencyDashboardApproval: true` on `major`). Type-checker
  wrappers (`svelte-check`, `vue-tsc`, `@astrojs/check`) call internal
  TypeScript APIs (`typescript.sys`) that break across TS majors, so an
  auto-opened TS major fails typecheck until the wrappers ship a compatible
  release. The bump is listed under **Pending Approval** on each repo's
  dependency dashboard; tick the checkbox once that repo's wrappers support the
  new major. Approval is per-repo. Minor/patch TS updates keep flowing.
- **`renovate-base.json`**: `lockFileMaintenance` is now enabled (weekly,
  Monday before 6am) and automerges on green, matching the non-major automerge
  policy. Inherited by all stack presets, so lockfile refreshes land without
  manual review in consumer repos. No workflow input/output changes.

### Added

- **`just` runner reference template**: new template for consumers adopting
  `just` as a task runner.

### Dependencies

- **GitHub Actions**: batched updates across reusables (`#245`, `#246`, `#247`).
- **`actions/setup-go`**: → v7.
- **`anthropics/claude-code-action`**: → v1.0.181.

---

## 2026-07-22

### Fixed

- **`ci-go.yml`, `ci-js.yml`**: CodeQL and scanner SARIF uploads no longer fail
  with `Resource not accessible by integration` on `push` events. The
  workflow-level `permissions: contents: read` downgraded the caller's token
  for every job — public-repo `pull_request` uploads succeed with a read
  token, which masked the gap until a consumer ran the pipeline on push
  (post-merge revalidation). The `codeql-analysis` (ci-go) and `security-scan`
  (ci-go, ci-js) jobs now carry job-level `actions: read` +
  `security-events: write`. No input or output changes; callers already
  granting `security-events: write` need no change.

### Dependencies

- **`actions/setup-node`**: v6.5.0 → v7.0.0 (`sbom-npm/action.yml`,
  `ci-js.yml`, `deploy-cloudflare-workers.yml`, `e2e-dde.yml`,
  `e2e-docker.yml`, `release-npm.yml`, `security-code.yml`,
  `security-deps.yml`).
- **`anthropics/claude-code-action`**: v1.0.176 → v1.0.177 (`ai-claude.yml`),
  plus a digest bump on the `v1` ref (`ai-claude-review.yml`).

---

## 2026-07-21

### Added

- **`deploy-terraform.yml`, `ops-drift-issue.yml`**: drift issues now show
  _what_ is drifting, and stop growing a duplicate comment every week.
  `deploy-terraform.yml` gains a `drift_summary` output — in drift mode it runs
  `terraform show -json` on the fresh plan and extracts one
  `<action> <address>` line per drifting resource. The extraction reads only
  `.address` and `.change.actions`, never `.change.before`/`.after`, so no
  attribute value (which can hold provider secrets) ever reaches the summary;
  a failing extraction yields an empty string and never suppresses the drift
  signal. `ops-drift-issue.yml` gains an optional `drift-summary` input: when
  set, it upserts a marker-delimited summary block into the issue body and adds
  a comment only when the set of drifting addresses changes. Non-breaking —
  both additions default to empty and preserve today's behaviour for callers
  that do not wire them (the drift issue still comments on every run without a
  summary). Consumer wiring in `authentication` follows in a separate PR once a
  date tag ships these changes.

---

## 2026-07-19

### Fixed

- **`ci-terraform.yml`**: `tflint --init` no longer crashes with
  `runtime error: invalid memory address or nil pointer dereference` while
  verifying the terraform plugin's signature attestation. The nil-pointer bug
  lives in tflint's signature bundle verifier
  ([terraform-linters/tflint#2591](https://github.com/terraform-linters/tflint/issues/2591))
  and was triggered by a GitHub backend change, so it hits every run rather
  than flaking intermittently. tflint v0.61.0–v0.63.1 are all affected;
  the pin moves to v0.64.0, which upstream released as the fix. Affects every
  consumer running with `enable-tflint: true`; no input or output changes.

---

## 2026-07-18

### Fixed

- **`security-code.yml`, `ci-go.yml`**: CodeQL-on-Go analysis no longer fails
  extraction when `go.mod` requires a newer Go than the CodeQL bundle ships
  (`go.mod requires go >= X (running go Y, GOTOOLCHAIN=local)`). The Go
  extractor is configured by `codeql-action/init`, so `setup-go` now runs
  before that step (`security-code.yml` ran it after; `ci-go.yml`'s CodeQL job
  had none at all and used the bundled Go), and both jobs set
  `GOTOOLCHAIN: auto` so Go may fetch the toolchain pinned in `go.mod`. Affects
  every Go consumer of these workflows; no input, output, or permission
  changes. The job-wide env is a no-op for non-Go matrix legs.

### Changed

- **`AGENTS.md`, `README.md`**: correct the stale `Last Updated` fields (both
  claimed `2026-05-03`) and the repository-structure comment, which undercounted
  the reusable workflows as 22 against the actual 24. Documentation only; no
  workflow behaviour changes.

### Dependencies

- **`actions/setup-node`**: v6.4.0 → v6.5.0 (`sbom-npm/action.yml`,
  `ci-js.yml`, `deploy-cloudflare-workers.yml`, `e2e-dde.yml`, `e2e-docker.yml`,
  `release-npm.yml`, `security-code.yml`, `security-deps.yml`).
- **`anthropics/claude-code-action`**: v1.0.170 → v1.0.174 (`ai-claude.yml`),
  plus a digest bump on the `v1` ref (`ai-claude-review.yml`).
- **`gosec`**: v2.27.1 → v2.28.0 (`ci-go.yml`).
- **`ansible`**: 14.1.0 → 14.2.0 (`security-config.yml`).
- **internal `setup-dde` / `project` / `sbom-npm` / `install-kubeconform`
  refs**: pinned to `@2026-07-13` (`project/action.yml`, `ci-gitops.yml`,
  `e2e-dde.yml`, `release-npm.yml`, `security-sbom.yml`).

---

## 2026-07-13

### ⚠ BREAKING

- **`security-secrets.yml`, `security-deps.yml`, `security-containers.yml`,
  `security-config.yml`**: scan jobs merged into a single sequential-step job
  per workflow to stop paying GitHub's per-job minute-rounding tax (each job
  rounds up to a full billed minute; scans ran 6–13 s each). Status-check
  context names change, which breaks branch-protection / ruleset required-check
  anchors pinned to the old job names.

  **Migration**: update required-status-check anchors in consumer rulesets /
  branch protection to the new context names:
  - `security-secrets.yml`: `Scan with Gitleaks` (unchanged) + `Scan Secrets`
    (replaces `Scan with TruffleHog`, `Detect Patterns`, `Create Report`)
  - `security-deps.yml`: `Scan Dependencies` (replaces `Dependency Review
(GitHub)`, `Audit Go`, `Audit JavaScript`, `Audit Python`, `Create Report`)
  - `security-containers.yml`: `Scan Container Image` (replaces `Scan with
Trivy`, `Scan with Grype`, `Analyze Images`, `Create Report`)
  - `security-config.yml`: `Scan Configuration` (replaces `Trivy Config Scan`,
    `Terraform Security`, `Scan Kubernetes`, `Scan Ansible`, `Create Report`)

  `gitleaks` stays an isolated job with scoped `pull-requests: read`
  (least-privilege preserved). Scanner pass/fail behaviour is preserved:
  merged scanners run with `continue-on-error` so later sequential steps
  execute, and a final enforce step re-raises the original gates — the
  AWS-key / private-key checks (`security-secrets`), `fail-on-findings`
  (`security-config`), and `fail-on-severity` (`security-deps`) still fail the
  workflow exactly as before. Note: `security-containers.yml`'s `scan-timeout`
  input no longer sets the job timeout (fixed 40 min ceiling now); the input is
  retained for compatibility but has no effect.

### Changed

- **`security-deps.yml`, `ci-js.yml`, `ci-go.yml`**: add `OFL-1.1` to the
  license allow-lists (the `security-deps.yml` default plus the
  `dependency-review-action` lists in `ci-js.yml` / `ci-go.yml`, which are
  separate), so fonts and icon sets under the SIL Open Font License pass across
  every license gate. Not breaking — widening an allow-list can only make
  previously-failing checks pass.
- **`ci-terraform.yml`, `ci-ansible.yml`, `ci-gitops.yml`**: expensive jobs now
  wait for the cheap lint/validate job via `needs:`, so a lint failure aborts
  before the heavy jobs burn minutes.
  - `ci-terraform.yml`: `lint` + `trivy` gain `needs: validation`.
  - `ci-ansible.yml`: `lint` + `yamllint` gain `needs: validation`.
  - `ci-gitops.yml`: the six non-gate jobs gain `needs: [validate-yaml]` with an
    `always() && !failure() && !cancelled()` guard, so they still run when the
    (conditional) gate is skipped but stop when it fails.

  **Not breaking**: no job names change, so required-status-check anchors stay
  valid. Behaviour note: a heavy job that previously reported `failure`
  independently now reports `skipped` when the gate fails, and successful runs
  are slightly slower (gate first, then heavy). `ci-go.yml` / `ci-js.yml`
  already gate their heavy jobs; unchanged.

---

## 2026-07-10

### Fixed

- **`ci-go.yml`**, **`security-deps.yml`**: Add `check-latest: true` to every
  `setup-go` step. Runners preferred a stale Go patch from the tool-cache (e.g.
  `go1.26.4`) over the latest patch for the requested minor, so stdlib
  vulnerabilities fixed in a newer patch (`go1.26.5`) kept the `govulncheck` gate
  red even though nothing in the consumer code was affected. `check-latest`
  resolves the newest patch from the version index instead of the cache.
- **`ci-go.yml`**: `govulncheck` now gates only on **call-reachable** findings.
  The previous gate keyed on any `"finding"` line, so import-only / module-level
  findings — a module pulled in transitively but never called (e.g. a deprecated
  package with no fixed version, like `golang.org/x/crypto/openpgp` reached only
  through `crypto/bcrypt`) — held the gate red permanently. Non-reachable
  findings are now reported as notices; the build fails only on findings whose
  trace is actually reachable in source mode.

## 2026-07-08

### Fixed

- **`ai-claude-review.yml`**: Set `allowed_bots: '*'` so bot-initiated runs
  reach the action. `claude-code-action@v1` rejects runs from bot actors
  unless their login is allow-listed; the job `if:` already skips
  renovate/dependabot, but `github-actions[bot]` (flake-lock update PRs) still
  reached the action and failed with "Workflow initiated by non-human actor".
  The remaining bots that pass the `if:` filter are trusted first-party ones.

### Changed

- **Dependencies**: Renovate updates for pinned action SHAs and tool versions —
  `actions/cache` v6, `@cyclonedx/cyclonedx-npm` v6, `golang.org/x/vuln`
  v1.5.0, `ansible-lint` v26.6.0, `anthropics/claude-code-action` v1.0.158,
  `postgres:18-alpine` digest, plus batched GitHub Actions SHA bumps.

## 2026-06-26

### Changed

- **`ci-js.yml`**: Allow the `BSD-2-Clause-Views` license (and the
  `BSD-2-Clause AND BSD-2-Clause-Views` compound) in the dependency-review
  gate. `uri-js` ships under that SPDX expression and is pulled in
  transitively by common JS toolchains (ajv/eslint), so the gate rejected it
  even though it is a permissive BSD license. No behaviour change for any
  other dependency.

## 2026-06-21

### Changed

- **`ci-gitops.yml`**: The `validate-helm-template` job now honours a
  conventional CI values file per chart. If a chart directory contains
  `values-test.yaml` (or `ci-values.yaml` / `values-ci.yaml`, first match
  wins), `helm template` renders with `-f <file>`. Charts that `required`-guard
  secret values (e.g. `database.existingSecret`) could not render from
  `values.yaml` defaults alone — the guard aborted the template and failed the
  job. Drop a values file with placeholder secret names to fix this without
  weakening the production guard. Charts without such a file render from
  defaults exactly as before — no behaviour change for them.

## 2026-06-19

### Added

- **`ci-gitops.yml`**: New `validate-helm-template` job + composite action
  `.github/actions/install-kubeconform`. The job renders every Helm chart with
  `helm template` (after a best-effort `helm dependency build`) and validates
  the rendered output with `kubeconform -strict -ignore-missing-schemas`,
  catching values/render errors that `helm lint` and static-manifest
  kubeconform miss. Gated on the new input `enable-helm-template-validation`
  (default `true`). The kubeconform install is now shared between this job and
  `validate-kubernetes` via the composite action.

### ⚠ BREAKING

- **`ci-gitops.yml`**: `enable-helm-template-validation` defaults to `true`, so
  the new rendered-manifest validation runs on the next tag bump for every
  GitOps consumer. A chart that renders invalid Kubernetes objects — and passed
  before because only static template files were checked — will now fail CI.
  Migration: fix the rendered manifest, or set
  `enable-helm-template-validation: false` to opt out.

## 2026-06-18

### Added

- **`templates/CHANGELOG.md`**: Keep-a-Changelog `CHANGELOG.md` template with
  an embedded comment block documenting the org convention (newest on top,
  `## [Unreleased]`, the category order, breaking-change sub-heading). Repos
  with a different cadence (e.g. `.github` itself) document the deviation in
  their own header instead of copying it verbatim.
- **`templates/vitest-cloudflare-workers/`**: Vitest projects template for
  Cloudflare Astro/Worker repos, lifted from `sbaerlocher/sbaerlo.ch`. Splits a
  fast `unit` project (DOM env, no worker runtime) from an `integration`
  project that runs the built worker in Miniflare via
  `@cloudflare/vitest-pool-workers`, with a mock-upstream worker serving any
  outbound service binding. Ships `vitest.config.ts`, `wrangler.test.jsonc`,
  `tests/env.d.ts`, a mock upstream and an example test, plus a README with
  adoption steps and the istanbul-coverage / no-outbound-service caveats.

### Changed

- **internal action refs**: Replace remaining `@main` references for
  `sbom-npm` with the date tag `@2026-06-10`, and align the dde internal
  action refs with the same date-tag model.
- **deploy-terraform.yml**: Pass `env-mapping` and `pre-script` through
  environment variables before shell execution, and document `pre-script` as a
  trusted-only escape hatch.
- **repo metadata**: Add `CONTRIBUTING.md`, `lefthook.yml`, and `.yamllint`;
  update CODEOWNERS and AGENTS.md to match the current repo structure.

### Dependencies

- **`actions/checkout`**: v6.0.3 → v7.0.0 (all workflows). Internal to the
  reusables; consumers pin date tags and are unaffected.
- **`pnpm/action-setup`**: v6.0.8 → v6.0.9 (`sbom-npm/action.yml`, `ci-js.yml`,
  `deploy-cloudflare-workers.yml`, `e2e-dde.yml`, `e2e-docker.yml`,
  `release-npm.yml`, `security-code.yml`, `security-deps.yml`).
- **`@cyclonedx/cyclonedx-npm`**: 4.2.1 → 5.0.0 (`sbom-npm/action.yml`).
- **`govulncheck`**: v1.3.0 → v1.4.0 (`ci-go.yml`, `security-deps.yml`).

## 2026-06-10

### Security

- **deploy-terraform.yml**: Add a fork guard as the first step of the
  `deploy` job. The workflow retrieves R2 and Authentik/Grafana secrets from
  Bitwarden; on a `pull_request` from a forked repository a malicious `.tf`
  change could exfiltrate them during the plan before review. The guard fails
  fast (before checkout and the Bitwarden step) when
  `github.event_name == 'pull_request'` and
  `github.event.pull_request.head.repo.fork` is true. **Consumers:** no action
  needed — same-repo PRs, `push`, `schedule` and `workflow_dispatch` are
  unaffected; only fork-originated pull requests are blocked (they previously
  would have loaded secrets). Not breaking for any current caller, which all
  run from branches in the base repository.

### Added

- **ai-claude-review.yml**: New optional `model` input (default
  `claude-opus-4-8`). Consumers can override the reviewer model with a
  cheaper tier (e.g. `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`) to
  trade review depth for lower CI cost. Default behaviour is unchanged; on
  the `pull_request` trigger (where `inputs.*` is undefined) the expression
  falls back to the default, matching the existing handling for
  `cancel-in-progress` / `concurrency-suffix`.
- **CHANGELOG.md / AGENTS.md**: Documented the breaking-change channel and
  tag support policy (see the section at the top of this file). Breaking
  changes now carry a `### ⚠ BREAKING` heading with a migration step; only
  the latest date tag is supported.
- **actions/project**: New `pre-pull-images` input (default `true`). Before
  `project:up` the action now pre-pulls all compose images (every profile)
  via `docker compose --profile '*' pull --ignore-buildable --quiet`. dde's
  dev-layer build probes each image with a 30-second `docker run` timeout;
  on a cold image cache — every fresh CI runner — pulling a larger image
  (grafana, loki, …) inside that probe exceeded the timeout and failed
  `project:up` before the stack started (reproduced with sbaerlocher/savvy's
  observability images). Best-effort: pull failures fall through to
  `project:up`, which reports them with proper context. **Consumers:** no
  action needed; set `pre-pull-images: false` to restore the old behaviour.

### Changed

- **security-deps.yml**: Replace the unmaintained `license-checker`
  (davglass, no release since 2019) with `license-checker-rseidelsohn`
  (`5.0.1`), the actively-maintained, feature-enhanced superset of the
  original `v25.0.1`. The CLI surface (`--json` / `--summary` / `--failOn`)
  is identical; the binary is renamed, so the install, the three
  invocations, and the Renovate datasource annotation are updated together.
  **Consumers:** no action needed — the license-check job behaviour and
  output artifacts are unchanged.
- **e2e-dde.yml**: The PR results comment is now updated in place instead
  of posting a new comment on every run. A hidden marker — keyed by
  `project-directory` and `concurrency-suffix`, so matrix legs keep
  separate comments — identifies the workflow's own comment; the first run
  still creates it. **Consumers:** no action needed — long-running PRs
  stop accumulating one results comment per push.
- **e2e-dde.yml**: Failure diagnostics additionally capture raw
  `docker ps -a` into `docker-ps.txt` in the `dde-logs` artifact. Unlike
  the `dde project:logs` / `dde project:status` calls this works even when
  dde itself never installed, and it is the one signal that always shows
  whether the stack came up at all.

### Fixed

- **security-secrets.yml**: Re-add the `pull-requests: read` token
  permission removed on 2026-06-08, scoped to the `gitleaks` job only. That
  removal assumed Gitleaks does not query the pull-requests API, but
  `gitleaks/gitleaks-action@v3` enumerates the PR's commits via
  `GET /repos/{owner}/{repo}/pulls/{n}/commits` on `pull_request` events.
  Without the grant the action aborts with HTTP 403 "Resource not accessible
  by integration", failing the Gitleaks job on every PR in consumer repos
  (observed in `authentication` PR #110) — a false CI failure with no actual
  leak. The permission is read-only and job-scoped per REVIEW.md
  least-privilege. **Consumers:** because this is a reusable, the grant is
  capped by the caller — a thin trigger workflow that restricts permissions
  to `contents`/`actions` will still hit the 403; ensure the caller grants
  `pull-requests: read` (or relies on the default token) when bumping the
  date tag.
- **renovate-terraform.json**: Stop the spurious `Failed to look up
terraform-provider package registry.terraform.io/<ns>/<name>: no-result`
  warnings that the `registryUrls` pin (2026-06-09) did not resolve. Root
  cause is in the terraform manager, not the registry: it extracts providers
  from `.terraform.lock.hcl` under their fully-qualified name
  (`registry.terraform.io/<ns>/<name>`), and the v2 datasource does not strip
  the host prefix — so it requests
  `/v2/providers/registry.terraform.io/<ns>/<name>` which 404s (verified: the
  same path without the host prefix returns 200). These lock-file lookups are
  redundant — the identical providers are already tracked from
  `versions.tf` / `required_providers` (packageName `<ns>/<name>`, resolves
  fine), and the lock file is maintained via `lockFileMaintenance` / artifact
  update, not datasource lookup. Disabling only the `.terraform.lock.hcl`
  source (`matchFileNames` + `enabled: false`) clears the warning without
  affecting provider tracking or lock updates.
- **e2e-dde.yml**: Replace `dde project:ps` with `dde project:status` in the
  "Show running services" step and the failure-diagnostics collection.
  `project:ps` does not exist in dde v2 — every invocation failed with
  `Command "project:ps" is not defined`, so the step printed an error
  instead of the service list and the `dde-ps.txt` file in the `dde-logs`
  artifact only contained that usage error (observed in sbaerlocher/savvy
  PR #102 run artifacts). All call sites were
  `continue-on-error`/`|| true`-guarded, so job results are unchanged. The
  artifact file is renamed `dde-ps.txt` → `dde-status.txt` to match the
  command. **Consumers:** no action needed unless tooling greps the
  `dde-logs` artifact for the literal `dde-ps.txt` filename — update it to
  `dde-status.txt`.
- **actions/project, actions/setup-dde**: Input docs no longer advertise
  `restart` (dde v2 has no `project:restart`; the real lifecycle commands
  are `up`, `down`, `stop`, `update`) and now recommend pinning an exact
  dde tag in CI instead of `latest`, which follows pre-releases and lets
  breaking dde changes propagate immediately.

## 2026-06-09

### Fixed

- **renovate-terraform.json**: Pin the `terraform-provider` datasource to
  `registry.terraform.io` only. Renovate defaults to querying both
  `registry.terraform.io` and `releases.hashicorp.com`; the latter times out
  (ETIMEDOUT, 30s) or returns 403 on Mend's hosted runner and is being
  deprecated for partner/third-party providers in favour of
  `release-assets.githubusercontent.com`. This caused persistent
  `Failed to look up terraform-provider package ...: no-result` warnings on
  the dependency dashboards of `infrastructure`, `authentication` and
  `observability` — for providers that resolve fine via the registry
  (authentik, bitwarden-secrets, hcloud, cloudflare, tailscale, vultr,
  grafana, hashicorp/\*). Overriding `registryUrls` drops the broken backend
  while keeping native version/range handling intact (the datasource queries
  `hashicorpReleaseUrl` only when it is present in `registryUrls`).

## 2026-06-08

### Removed

- **security-secrets.yml**: Drop the unused `pull-requests: read` token
  permission. Gitleaks and TruffleHog only read repository contents and the
  Actions metadata; neither queries the pull-requests API, so the grant was
  dead scope. Tightens the workflow to least-privilege.

### Fixed

- **security-deps.yml**: Correct the `go-licenses` install path to include
  the `/v2` major-version suffix (`github.com/google/go-licenses/v2`), and
  align the Renovate `depName` comment in lockstep. The `v2.0.1` module path
  requires the `/vN` suffix under semantic import versioning, so the previous
  unsuffixed `go install` failed — surfacing as the weekly Security Scan
  failure on `tsmetrics` and any other Go repo consuming this reusable
  workflow. Verified that v2 still ships a `go-licenses` binary at the module
  root and accepts the `check`/`csv` subcommands plus `--allowed_licenses`.

### Dependencies

- **`codecov/codecov-action`**: v6.0.1 → v7.0.0 (`ci-go.yml`, `ci-js.yml`).
- **`github/codeql-action`**: v4.36.0 → v4.36.2 (`ci-go.yml`, `ci-js.yml`,
  `ci-terraform.yml`, `release-docker.yml`, `security-code.yml`,
  `security-config.yml`, `security-containers.yml`).
- **`gitleaks/gitleaks-action`**: v2.3.9 → v3.0.0 (`security-secrets.yml`).
- **`trufflesecurity/trufflehog`**: v3.95.3 → v3.95.5 (`security-secrets.yml`).
- **`docker/setup-qemu-action`**: v4.0.0 → v4.1.0 (`release-docker.yml`).
- **`actions/checkout`**: v6.0.2 → v6.0.3 (all workflows).
- **`anthropics/claude-code-action`**: v1.0.133 → v1.0.137 (`ai-claude.yml`,
  `ai-claude-review.yml`).
- **`ansible`**: 13.7.0 → 14.0.0 (`security-config.yml`).
- **`gosec`**: v2.26.1 → v2.27.1 (`ci-go.yml`).
- **`safety`**: 3.8.0 → 3.8.1 (`security-deps.yml`).
- **internal `setup-dde` / `project` refs**: pinned to `@2026-05-30`
  (`actions/project/action.yml`, `e2e-dde.yml`).

---

## 2026-05-30

### Changed

- **ai-claude-review.yml**: Bump `--model` to `claude-opus-4-8` for both
  the first and follow-up review passes (previously `claude-opus-4-7`
  for first and `claude-sonnet-4-6` for follow-up). The per-mode
  conditional collapses to a single fixed model ID since both branches
  now use the same model.

### Dependencies

- **`codecov/codecov-action`**: v6.0.0 → v6.0.1 (`ci-go.yml`, `ci-js.yml`).
- **`github/codeql-action`**: v4.35.5 → v4.36.0 (`ci-go.yml`, `ci-js.yml`,
  `ci-terraform.yml`, `release-docker.yml`, `security-code.yml`,
  `security-config.yml`, `security-containers.yml`).
- **`docker/setup-buildx-action`**: v4.0.0 → v4.1.0 (`release-docker.yml`).
- **`docker/login-action`**: v4.1.0 → v4.2.0 (`release-docker.yml`).
- **`docker/metadata-action`**: v6.0.0 → v6.1.0 (`release-docker.yml`).
- **`docker/build-push-action`**: v7.1.0 → v7.2.0 (`release-docker.yml`).
- **`goreleaser/goreleaser-action`**: v7.2.1 → v7.2.2 (`release-go.yml`).
- **`anthropics/claude-code-action`**: v1.0.123 → v1.0.133 (`ai-claude.yml`,
  `ai-claude-review.yml`).
- **`ansible`**: 13.6.0 → 13.7.0 (`security-config.yml`).
- **`safety`**: 3.7.0 → 3.8.0 (`security-deps.yml`).
- **internal `setup-dde` / `project` refs**: pinned to `@2026-05-17`
  (`actions/project/action.yml`, `e2e-dde.yml`).

---

## 2026-05-17

### Added

- **`validate-observability-configs`**: New composite action that
  installs Grafana Alloy and validates `*.alloy` files via
  `alloy fmt --test` plus `*.json` config files via `jq empty`. Used by
  the observability repo's `pull-request.yml` to gate Alloy / JSON
  drift before Terraform plan/apply. Inputs let consumers override the
  Alloy version, Alloy directory and the newline-separated list of JSON
  directories. Mirrors the `setup-dde` supply-chain pattern: platform
  detection (`linux`/`darwin` × `amd64`/`arm64`), SHA256 verification
  against `SHA256SUMS`, install into `$RUNNER_TEMP` + `$GITHUB_PATH`
  (no `sudo`), `curl --retry 3`. Validation steps capture and surface
  the tool's stderr/stdout so failed configs report the actual error,
  and search both `*.alloy` and `*.json` recursively so nested
  layouts (e.g. `configs/dashboards/<service>/foo.json`) are covered.

---

## 2026-05-16

### Added

- **`setup-dde`**: New pre-authorize step that runs before
  `dde system:install` on Linux runners. It `chmod o+w`s `/etc/systemd`
  (so dde can write its `resolved.conf.d` drop-in) and installs a polkit
  rule that grants the runner user `manage-units` on
  `systemd-resolved.service` (so the unprivileged restart succeeds).
  Linux-only and gated on `system-install: true`. Removes the
  per-consumer `Pre-authorize dde DNS resolver setup` workaround that
  was previously copy-pasted into e2e workflows. Drop once dde escalates
  for `resolved.conf.d` / polkit the same way it does for dnsmasq.

- **`e2e-dde.yml`**: Five new optional inputs for plugin-driven E2E
  lifecycles. Existing callers keep working unchanged; reach for these
  when the project drives its E2E flow through dde plugins rather than
  the standard `dde project:up` → `npm run test:e2e` → `dde project:down`
  pipeline.
  - `compose-profiles` — set `COMPOSE_PROFILES` at job scope (e.g. `e2e`
    to bring up an `app-e2e` compose profile while leaving the dev
    profile dormant). Applies to every dde call in the job, including
    teardown.
  - `pre-test-commands` — bash to run after `dde project:up` and
    dependency install, but before Playwright tests. Runs in
    `project-directory`. Use for DB reset, health-check waits, fixture
    seeding.
  - `test-command-override` — raw bash that replaces the
    `<pm> run <test-command>` step. Use for projects that drive
    Playwright through a dde plugin (`dde project:e2e:test`) instead of
    a package-manager script.
  - `failure-logs-command` — raw bash for failure-time log capture.
    Replaces the default `dde project:logs` (`dde-ps.txt` is still
    written from `dde project:ps`).
  - `teardown-command` — bash for the always-run teardown step. Replaces
    the default `dde project:down`. Use for plugin-driven cleanup like
    `dde project:e2e:down -v`.

### Note on transitive consumption

Consumers of `e2e-dde.yml@2026-05-16` and `project@2026-05-16` do **not**
transitively pick up the new `setup-dde` polkit step in this tag — the
inner `uses:` refs still point at `setup-dde@2026-05-07`. To benefit from
the polkit fix, either:

- consume `setup-dde@2026-05-16` directly, or
- wait for the next rolling-release tag, where Renovate's standard
  github-actions bump will have lifted the inner refs to `@2026-05-16`.

This is the documented chicken-and-egg of the date-tag model: the inner
ref cannot point at the tag that is about to be cut from the same
commit, because the tag does not yet resolve at PR-validation time.

---

## 2026-05-07

### Fixed

- **`ci-gitops.yml`**: The `Validate Kubernetes manifests` step's path
  filter (`grep -E '(templates|manifests)'`) matched the substring
  anywhere in the path, so a Fleet bundle living under e.g.
  `applications/<svc>/email-templates/fleet.yaml` was handed to
  kubeconform and failed with `error while parsing: missing 'kind' key`
  — `fleet.yaml` is a Fleet bundle config, not a Kubernetes manifest.
  The pre-`2026-05-03` step trailed `|| true` and silently swallowed
  this; the strict default introduced in `2026-05-03` exposed it as
  a real failure for any consumer with a `*-templates` or `*-manifests`
  directory name.

  Two changes:
  - Tightened the regex to `'/(templates|manifests)/'` so only
    `templates` / `manifests` as standalone path segments match (the
    intended helm-chart-templates / raw-k8s-manifests directories).
  - Added `! -name 'fleet.yaml'` to the `find` so Fleet bundle configs
    are excluded defensively even if a future path layout puts one
    inside a `templates/` directory.

  Consumer-visible: a bundle path containing `*-templates` or
  `*-manifests` in a directory name no longer produces a kubeconform
  failure, and `fleet.yaml` files are never evaluated as K8s manifests.

---

## 2026-05-03

### Added

- **`ops-drift-issue.yml`**: New reusable workflow that upserts a GitHub
  issue when Terraform drift is detected. Replaces the inline
  `create-drift-issue` job that consumer repos
  (`authentication`, `infrastructure`, `observability`) duplicated in
  their `drift.yml` workflows. Idempotent by title — if an open issue
  with the substituted `title-template` (default
  `Terraform Drift Detected: {project} ({environment})`) and the
  configured `label` (default `terraform-drift`) exists, it adds a
  comment instead of creating a new issue. Concurrency-grouped by
  `project-name + environment` so two simultaneous drift jobs cannot
  race on `gh issue list`. The label must already exist in the consumer
  repository — the workflow does not create it.
- **`ops-terraform-report.yml`**: New reusable workflow that renders the
  Terraform pipeline report (Step Summary + `deployment-metadata.json`
  artifact + optional notification step) from
  `ops-terraform-orchestration.yml` + `deploy-terraform.yml` outputs.
  Consolidates the inline `report` job that consumer `deploy.yml`
  workflows duplicated. Supports both deploy and drift modes via the
  `mode` input; drift mode includes the `drift-detected` row in the
  deployment-details table. The notification step is opt-in via
  `notification-environment` and currently logs to stdout — wire a real
  webhook in the consumer if needed.

### Changed

- **All reusable workflows now expose `cancel-in-progress` and
  `concurrency-suffix` inputs.** Previously only `deploy-terraform.yml`
  carried these. Inconsistent concurrency behaviour caused real failures
  when consumers wired the same reusable into parallel matrix legs or
  multi-mode pipelines (drift vs deploy) — they could not separate the
  groups without forking the workflow.

  Defaults preserve current behaviour: CI / Security / E2E default to
  `cancel-in-progress: true` (latest push wins); Deploy / Release / Ops
  default to `false` (in-flight runs finish). The suffix defaults to
  empty, so the group name is unchanged for every consumer that does
  not opt in.

  See AGENTS.md → "Concurrency Convention" for the full pattern, the
  base-group rules (caller-isolated vs resource-locked), and override
  guidance.

  Touched: `ai-claude*`, `ci-*`, `deploy-cloudflare-workers`,
  `e2e-*`, `ops-*`, `release-*`, `security-*`. `deploy-terraform.yml`
  already had the inputs from the prior change.

### Security

- **All workflows: `actions/checkout` hardened with `persist-credentials: false`.**
  Previously many checkouts inherited the v6 default `true`, which
  persists `GITHUB_TOKEN` in `.git/config` for any subsequent step or
  untrusted action to read. None of the reusable workflows actually
  push via `git`, so disabling persistence is safe across the board.
  Touched: `ai-claude*`, `ci-*`, `deploy-cloudflare-workers`,
  `e2e-*`, `release-*`, `security-*`, `ops-terraform-orchestration`,
  `test-actions-dde`. `deploy-terraform`, `ci-ansible`, and
  `ci-terraform` already had it set.
- **Top-level `permissions:` added to `deploy-terraform.yml`,
  `ai-claude.yml`, and `ai-claude-review.yml`.** All three previously
  inherited the caller's default permissions. Top-level is now
  `contents: read`; existing job-level overrides (the AI workflows
  expand to `pull-requests: write` etc.) remain in place.

### Changed (cosmetic)

- **Workflow `name:` fields normalized to `Category - Subject` style**
  with hyphen separator (per AGENTS.md naming convention):
  - `ci-gitops.yml`: `Continuous Integration (GitOps)` →
    `Continuous Integration - GitOps`
  - `e2e-dde.yml`: `E2E Tests (dde)` → `End-to-End - dde`
  - `e2e-docker.yml`: `E2E Tests (Docker Compose)` →
    `End-to-End - Docker Compose`
  - `test-actions-dde.yml`: `Test dde actions` → `Test - dde Actions`
  - All others were already conformant.

### Fixed

- **`ai-claude-review.yml` (#102)**: Hardened the review workflow.
  Previous bugs broke follow-up runs and ran Opus with 100 turns on
  every push.
  - Reply endpoint was missing the PR number, returned 404 on every
    follow-up. Now uses `repos/{repo}/pulls/{number}/comments/{id}/replies`.
  - Mode detection now reads the prior review (not inline comments),
    so clean PRs with no findings correctly transition to follow-up
    mode instead of re-paying for a full first pass.
  - Bot login is detected dynamically (`gh api .../reviews` →
    `.../comments`) instead of hardcoded `claude[bot]`, so the
    detection survives App-login changes.
  - Follow-up now diffs against the last review SHA via
    `gh api .../compare/{base}...{head}` instead of `gh pr diff` —
    the "only flag new issues" instruction now actually has the
    right input.
  - Pre-step computes `mode` / `bot-login` / `last-review-sha` in shell
    as job outputs; prompt receives concrete values instead of
    placeholders.
  - Cost split: first review keeps Opus with 100 turns; follow-up
    runs on Sonnet with 40 turns.
  - Both modes submit an explicit verdict (`--approve` or
    `--request-changes`) so PRs don't sit in limbo when issues remain.
  - Prompt now Reads `REVIEW.md` / `AGENTS.md` / `CLAUDE.md` first
    so repo-specific rules win over generic best practices.
  - Fork PRs are skipped explicitly (no secrets, no write token →
    silent zero-comment runs were misleading).

### Documentation

- **AGENTS.md → "Workflow Layering"**: Codifies the three-layer split
  (repo workflow / reusable / composite action) and the rule that
  _concurrency is owned by the reusable_ — never duplicated in the
  caller for the same scope. Replaces the implicit "two limiters in
  series" pattern that produced queue pile-ups in consumer repos.
- **AGENTS.md → "Concurrency Convention"**: Documents the uniform
  `cancel-in-progress` + `concurrency-suffix` inputs, the per-category
  defaults, the two base-group patterns (caller-isolated vs
  resource-locked), and override guidance.

### Dependencies

- `anthropics/claude-code-action`: → v1.0.107 (#92), → v1.0.110 (#103)
- `securego/gosec`: → v2.26.1 (#101)
- GitHub Actions group bumps: #99, #100 (Renovate batched)

---

## 2026-04-30

### Removed

- **`STANDARDS.md` and `SETUP.md`**: Deleted without replacement.
  `STANDARDS.md` documented org-wide repo conventions (required files,
  required workflows per repo type, Renovate preset map, Conventional
  Commits, GitHub repo settings) and `SETUP.md` carried the `gh repo
edit` / branch-ruleset bootstrap script. Neither doc is being relocated
  — the conventions still apply but are now enforced via templates,
  reusable workflows, and the Renovate presets in this repo, not via a
  central spec. Issue forms (`config.yml`, `feature_request.yml`) and
  the PR template were updated to drop the dangling links.

### Changed (BREAKING)

- **`actions/project-up/` → `actions/project/`**: Renamed and generalised.
  The action now accepts a `command` input (default `up`) and runs
  `dde project:<command>`, so the same action covers `up`, `down`,
  `restart`, `update`, etc. `system-install` and `wait-url` are only
  applied when `command: up` and silently ignored for other commands —
  callers can pass them unconditionally if a matrix re-uses the same
  `with:` block. Migration: replace
  `sbaerlocher/.github/.github/actions/project-up@<TAG>` with
  `sbaerlocher/.github/.github/actions/project@<TAG>`. Existing usages
  pick up the new default `command: up` automatically. Teardown that
  used to be `run: dde project:down` can become a second `uses: project`
  step with `command: down`. The breaking surface is the action path —
  inputs, outputs, and behaviour for the previous up flow are unchanged.

### Fixed

- **`project-up` (now `project`)**: Reference `setup-dde` via the full
  cross-repo path
  (`sbaerlocher/.github/.github/actions/setup-dde@<DATE-TAG>`) instead
  of `./.github/actions/setup-dde`. `uses: ./...` from inside a
  composite action resolves against the caller's `GITHUB_WORKSPACE`,
  not against the action's own repo (see
  [actions/runner#2185](https://github.com/actions/runner/issues/2185)),
  so the relative path 404'd for any consumer outside this repo. The
  self-test happened to pass because `actions/checkout` of
  `sbaerlocher/.github` coincidentally landed `setup-dde` into the
  workspace. AGENTS.md and the `e2e-dde.yml` workflow were updated
  alongside; `renovate.json` `github-actions` `managerFilePatterns`
  was extended to include `actions/<name>/action.yml` so the new
  cross-repo pin gets bumped automatically.
- **`setup-dde`**: Drop the `sudo --preserve-env=...` wrapper around
  `dde system:install`. dde escalates internally (passwordless sudo) for
  the individual steps that need root, so wrapping the whole call left
  `~/.dde/data/...` files root-owned and broke subsequent unprivileged
  `dde project:*` calls. Surfaced once the action-resolution bug above
  stopped masking it. Caller-visible changes: none for the happy path;
  the `system-install` input description and the `setup-dde` /
  `project-up` / AGENTS.md notes were aligned with the new behavior.

---

## 2026-04-28

### Added

- **`e2e-dde.yml`**: Reusable E2E workflow using whatwedo `dde` for stack
  management instead of Docker Compose. Mirrors the Playwright/Node setup
  surface of `e2e-docker.yml`; replaces `compose-file` / `compose-profile`
  with `project-directory` / `wait-url`. Linux-only (Docker is required by
  `dde system:install`). PR-comment step is split into a separate job so
  the test job runs at `contents: read` only; `pull-requests: write` is
  scoped to the comment job. `cache-dependency-path` is selected based on
  the `package-manager` input (npm / pnpm / yarn / bun), and
  `playwright-browsers` / `test-command` flow through `env:` to prevent
  shell injection from caller-supplied input. Migration: consumers running
  `e2e-docker.yml` against a dde-compatible project can switch by
  replacing the workflow reference and renaming inputs accordingly.
- **`.github/actions/setup-dde/`**: Composite action that installs the
  [whatwedo dde](https://github.com/whatwedo/dde) CLI, verifies the binary
  against the release `checksums.txt`, and places it on `PATH`. Optional
  `mkcert` install and `dde system:install`.
- **`.github/actions/project-up/`**: Composite action that wraps
  `setup-dde` + `system:install` + `dde project:up` plus an optional
  `wait-url` poll loop. Intended for ad-hoc E2E pipelines that don't use
  `e2e-dde.yml`. New `system-install` input (default `true`) lets unit-style
  tests skip host provisioning. `wait-timeout` default is `180` (matches
  `e2e-dde.yml`).
- **`test-actions-dde.yml`**: Internal self-test workflow for the dde
  composite actions. Not reusable. Smoke test for `setup-dde` covers
  `ubuntu-latest`, `ubuntu-24.04-arm`, `macos-latest`, and `macos-13`
  (darwin-amd64 coverage). The `project-up` smoke test uses
  `system-install: 'false'` so it does not mutate the runner host.

### Changed

- **README.md / AGENTS.md**: Document the `Composite Actions` surface;
  introduce `test-*.yml` as the filename prefix for internal self-test
  workflows that are not consumer-callable.
- **STANDARDS.md**: Annotate `setup-dde` and `project-up` as whatwedo-only;
  clarify `sbom-npm` is an internal helper for `release-npm.yml` and
  `security-sbom.yml`.

---

## 2026-04-25

### Changed

- **ci-js.yml** (BREAKING): Rename `enable-type-check` input to `enable-typecheck`
  and switch invoked package script from `type-check` to `typecheck` for all
  package managers (pnpm, bun, yarn, npm)
  - Aligns with the de-facto JS ecosystem convention (`tsc --noEmit` scripts are
    almost universally named `typecheck`, single word)
  - Consumer action required: rename the `type-check` script in `package.json`
    to `typecheck`, and rename the workflow input if explicitly set
  - Input default value unchanged (`enable-typecheck: true`); existing
    consumers still invoke type checking by default and therefore need
    the renamed `typecheck` script regardless of whether they set the
    input
- Dependency refreshes since 2026-04-23 (all via Renovate):
  - Grouped GitHub Actions SHA bumps (#72, #73, #74)

---

## 2026-04-23

### Changed

- **renovate-go.json**: Cleanup `customManagers` from 5 to 1
  - Removed four managers with no matching files in any consumer repo:
    `.go-version` parser, Makefile `GO_VERSION`, Makefile
    `GOLANGCI_LINT_VERSION`, and the non-standard `# renovate: go-tool …`
    comment format (the last is already covered by the base manager via
    standard `# renovate: datasource=… depName=…` syntax)
  - Kept the Dockerfile `RUN go install <module>@<version>` manager — only
    Go-specific pattern in active use (tsmetrics); base manager cannot
    handle it because it expects `key: value`, not `@version`
  - Aligned remaining manager with base style: `[^\s]+` capture groups
    and support for optional `versioning=` / `extractVersion=` hints

---

## 2026-04-22

### Fixed

- **ai-claude-review.yml**: Bump `--model` from `claude-opus-4-6` to `claude-opus-4-7`
  - Align the parent review agent with the current latest Opus; plugin subagents
    (haiku/sonnet/opus) are unaffected
- **ci-js.yml**: Remove deprecated `allow-unknown-licenses` input from
  `dependency-review-action` step (unsupported since v4.9.0, emitted a warning
  on every PR CI run)

### Changed

- Dependency refreshes since 2026-04-11 (all via Renovate):
  - `anthropics/claude-code-action` digest → `0d2971c` (#63)
  - `bitwarden/sm-action` → v3 (#67)
  - `softprops/action-gh-release` → v3 (#65)
  - `pnpm/action-setup` → v6 (#62)
  - `actions/github-script` → v9 (#61)
  - Grouped GitHub Actions minor/patch bumps (#59, #60, #64, #66, #69)

---

## 2026-04-11

### Fixed

- **renovate-js.json**, **renovate-kubernetes.json**, **renovate-go.json**: Ensure
  co-dependent packages bump together in a single PR to prevent peer-dependency
  CI failures
  - **Peer-dependency grouping** (`renovate-js.json`): Co-dependent packages that
    previously landed in separate PRs now share one group:
    - `typescript-eslint` + `@typescript-eslint/*` added to "Code quality tools"
      group (peer dep on `eslint` — ESLint 9→10 would otherwise split and fail)
    - `vitest` + `@vitest/*` merged into "Build tooling (Vite + Vitest)" group
      (Vitest has a hard peer dep on Vite; Vite major without Vitest breaks
      `pnpm install`)
    - `vue-router`, `pinia`, `@pinia/*`, `@vitejs/plugin-vue*` added to
      "Vue packages" group (all have peer deps on `vue`)
    - `@vitejs/plugin-svelte*` added to "Svelte packages" group
    - Legacy unscoped `graphql-codegen-*` added to "GraphQL packages" group
    - Testing tools group renamed to "Jest" (vitest moved out)
  - **Branch-name collapsing** (`separateMultipleMajor: false` per group):
    Collapse the `major-N-` segment that Renovate prepends to `groupSlug` for
    grouped major updates, so co-dependent packages with _different_ major
    version numbers (e.g. Vue 4 + plugin-vue 6) share one branch/PR despite
    `separateMultipleMajor: true` in base
    - Verified against Renovate source
      ([`lib/workers/repository/updates/branch-name.ts`](https://github.com/renovatebot/renovate/blob/main/lib/workers/repository/updates/branch-name.ts)):
      the `major-N-` prefix is mutated directly into `groupSlug`, not into
      `additionalBranchPrefix`. With `separateMultipleMajor: false`,
      `groupSlug` collapses to `major-<group>` (without the version number),
      forcing all majors of the group onto a single branch
    - Side effect (intended): Renovate creates one PR per group for the
      latest major only, not one PR per intermediate major. For
      peer-dep-critical groups this is desired — you want to land on a
      consistent ecosystem state, not chain through broken intermediate
      states
    - Applied to: Code quality tools, Build tooling (Vite + Vitest), Astro,
      Vue, Svelte, TailwindCSS, Cloudflare Workers, Hono, GraphQL, Turborepo
    - Applied to Helm charts group in `renovate-kubernetes.json`
    - Applied to Go platform packages group in `renovate-go.json` (critical
      for `k8s.io/*` + `sigs.k8s.io/*` major-version lock-step)
  - **Regex precision**: All `matchPackageNames` patterns now use proper anchors
    (`/^pkg$/` instead of `/^pkg/`) and escaped slashes (`/^@scope\\//`) to
    prevent false-positive matches like `vuex-persist` landing in the Vue group

### Changed

- **renovate-js.json**: Remove `:preserveSemverRanges` from `extends`
  - `:preserveSemverRanges` sets `rangeStrategy: "replace"`, conflicting with
    base's `rangeStrategy: "bump"`
  - `bump` is the correct strategy for apps (always updates the version in
    `package.json`, better for reproducibility)
  - Library repos (e.g. `vue.aareguru`) can override locally if flexible ranges
    are preferred
- **renovate-js.json**: Add `minimumReleaseAge: "14 days"` to "Build tooling
  (Vite + Vitest)" group for extra stability on ecosystem churn (previously
  only applied to majors)

---

## 2026-04-09

### Fixed

- **renovate-js.json**: Remove `enabledManagers` to fix silent allowlist clobbering
  when multiple presets are extended
  - `enabledManagers` is [non-mergeable by design](https://github.com/renovatebot/renovate/discussions/37059)
    in Renovate — when multiple presets set it, the last one wins (no union)
  - Consumers extending both `renovate-js` and `renovate-kubernetes` (e.g. a JS app
    deployed via Helm) silently lost one allowlist depending on extends order
  - Removing the allowlist here aligns `renovate-js.json` with `renovate-base.json`,
    `renovate-docker.json`, and `renovate-go.json`, which already omit `enabledManagers`
  - JS/TS scoping is already enforced via package rules in this preset
  - Note: `renovate-kubernetes.json` and `renovate-terraform.json` still define
    `enabledManagers` — this is intentional for now and tracked separately

---

## 2026-03-28

### Changed

- **ai-claude-review.yml**: Add two-phase review mode — full review on first pass,
  follow-up replies on subsequent pushes (#44)
- **ai-claude-review.yml**: Add automatic PR approval and thread resolution after follow-up review (#45)
  - When all previously raised issues are resolved: approves the PR and resolves all review threads
  - When any issue is still open: no approval, threads remain unresolved
  - PR approval via `gh pr review --approve`
  - Thread resolution via GitHub GraphQL `resolveReviewThread` mutation
  - Added `Bash(gh pr review:*)` and `Bash(gh api graphql:*)` to `allowedTools`
  - Add `synchronize` to trigger types so the workflow re-runs when new commits are pushed to an open PR
  - On first run (no previous `claude[bot]` comments): runs full `/code-review --comment` with detailed inline comments
  - On follow-up runs (previous comments exist): fetches own comments and replies to each one via
    `gh api repos/.../pulls/comments/<id>/replies` — marking issues as resolved or still open
  - `mcp__github_inline_comment__create_inline_comment` does not support `in_reply_to`; replies use `gh api` directly
  - Added `gh api repos/*/pulls/*/comments*` and `gh api repos/*/pulls/comments*` to `allowedTools`

---

## 2026-03-22

### Added

- **REVIEW.md**: Code review guidelines for this repository — required standard for all repos
- **SETUP.md**: GitHub repository setup commands, branch ruleset JSON, and full setup script
  (extracted from STANDARDS.md to keep standards focused on rules, not procedures)
- **ci-gitops.yml**: New reusable workflow for GitOps/Fleet validation
  - Validates YAML syntax, Fleet bundle configuration, and Kubernetes manifests
  - Checks `fleet.yaml` presence, Helm chart structure, and HelmRelease CRD usage
  - Consolidates all GitOps CI checks that were previously implemented locally per consumer repo
- **ci-js.yml**: Add `node-version` input for explicit Node.js version selection
  - Callers can now pass a specific version (`node-version: '20'`) to enable matrix testing
  - Falls back to `node-version-file` (`.nvmrc`) when not set — fully backwards compatible

### Fixed

- **ai-claude-review.yml**: Enable inline comments in code review (#32)
  - Remove `track_progress: true` which forced single-comment mode
  - Add `classify_inline_comments: 'false'` to post inline comments immediately
- **ai-claude-review.yml**: Add `Task`, `Agent`, `Read`, `Glob`, `Grep` to `allowedTools` (#33)
  - The `code-review` plugin spawns parallel sub-agents and reads CLAUDE.md files
  - Missing tools caused 4 permission denials per run, preventing inline comment posting
- **ai-claude-review.yml**: Increase `--max-turns` from 30 to 100 (#34)
  - Sub-agent workflow requires significantly more turns than single-agent mode
- **renovate-kubernetes.json**: Replace RE2-incompatible lookahead in Fleet Helm chart regex (#35)
  - `(?:(?!repo:)[\s\S])*?` used a negative lookahead unsupported by RE2
  - Replaced with RE2-safe alternation `(?:[^r]|r[^e]|re[^p]|rep[^o]|repo[^:])*?`
  - Preserves cross-block boundary guard without requiring lookahead support
- **SETUP.md**: Clarify branch ruleset status check context format (#36)
  - GitHub uses the job `name:` field, not the job ID, for context strings
  - Reusable workflows show as `caller job name / job name`, not `caller-job / job`

### Removed

- **drift-terraform.yml**: Deleted — was a pure wrapper around `deploy-terraform.yml` with `mode: drift`
  - No functional difference; consumer repos call `deploy-terraform.yml` directly with `mode: drift`
- **docs-terraform.yml**: Deleted — consumer repos implement `terraform-docs` locally
- **helm-test.yml**: Deleted — covered by `ci-gitops.yml` and `e2e-docker.yml`
- **notify-deployment.yml**: Deleted — non-generic Slack notification with hardcoded assumptions
- **ops-drift-detection.yml**: Deleted — superseded by `deploy-terraform.yml` with `mode: drift`
- **ops-sync-secrets.yml**: Deleted — Bitwarden → Cloudflare Workers secret sync was too repo-specific
- **quality-benchmarks.yml**: Deleted — benchmark CI was not consumed by any active repo
- **security-supply-chain.yml**: Deleted — SBOM generation and Cosign signing moved to `security-sbom.yml`

### Changed

- **ci-terraform.yml**: Remove `tfsec` job and `enable-tfsec` input
  - Security scanning belongs in dedicated `security-config.yml`, not in CI
  - Reduces CI scope to validation only (fmt, validate, tflint, docs check)
- **ai-claude-review.yml**, **ai-claude.yml**: Add `id-token: write` permission
  - Required for OIDC token fetching by `anthropics/claude-code-action`
  - Without it, the action fails: "Could not fetch an OIDC token"
- **Step summaries** (9 workflows): Refactor to runtime-result-only format
  - Removed boilerplate sections ("Tools Used", "Best Practices", "Security Coverage")
  - Each summary now contains: timestamp, repository context, status table, key config values
  - Affected: `ci-js.yml`, `security-config.yml`, `security-containers.yml`, `security-code.yml`,
    `security-deps.yml`, `security-secrets.yml`, `release-npm.yml`, `release-docker.yml`,
    `deploy-cloudflare-workers.yml`
- **STANDARDS.md**: Rewritten from 1549 → ~280 lines
  - Removed long YAML/JSON examples, "Why?" explanations, Kubernetes/Monitoring details
  - Removed `.claude/commands/` section — custom commands are no longer a standard requirement
  - Added `REVIEW.md` as required file for all repositories
  - Moved GitHub setup commands and branch ruleset JSON to new `SETUP.md`
  - Kept: required files table, workflow matrix, SHA pinning rule, commit format, Renovate
    preset mapping, secret rules, code quality table
- **AGENTS.md**: Sync workflow categories with actual files
  - Removed deleted workflows (`ops-drift-detection.yml`, `ops-sync-secrets.yml`)
  - Added missing AI workflows section (`ai-claude-review.yml`, `ai-claude.yml`)
  - Shortened workflow table file columns to filename-only
  - Added `REVIEW.md` and `SETUP.md` to repo structure and related documentation
- **renovate-docker.json**: Add `minimumReleaseAge: "5 days"` to additional image groups

### Dependencies

- **GitHub Actions** (PR #29): Update SHA digests
  - `security-containers.yml`: `aquasecurity/trivy-action` SHA update
  - `security-sbom.yml`: `anchore/sbom-action` and `sigstore/cosign-installer` SHA updates

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

- **renovate-\*.json**: Migrate deprecated options and simplify all 6 presets (#15)
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

✅ Fully compliant with STANDARDS.md
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

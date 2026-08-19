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
- **Only the latest tag is supported.** Past days' tags keep working and no
  longer move, but fixes and security patches land only on `main` / the newest
  tag. Pin an old tag at your own risk; there is no backport. The current UTC
  day's tag is the exception: it follows that day's latest merge, so it can
  still change until the day is over.

---

## 2026-08-19

### ⚠ BREAKING

- **`ci-js.yml` drops the `Setup` job and reports one security check instead of
  three.** `Setup` wrote `tests=true` and `security=true` as literals, so both
  `if:` gates reading them were constant, and its `fetch-depth: 0` checkout was
  thrown away by the next job checking out again — a full billed minute per run
  in six repos for no work. The security scanners were a three-leg matrix whose
  every step was gated on its own `matrix.scanner` value: the legs shared no
  work, only a job body, and paid three runner starts for it. Both are gone;
  the scanners now run as sequential steps in one `Security` job.
  **Migration:** a consumer whose branch protection or ruleset lists
  `<caller-job> / Setup`, `<caller-job> / Security (dependency-audit)`,
  `<caller-job> / Security (trivy-fs)` or `<caller-job> / Security (trivy-deps)`
  must drop the `Setup` entry and replace the three `Security (…)` entries with
  the single `<caller-job> / Security` before bumping the tag. None of the six
  current consumers requires any of these names today, so no ruleset needs
  changing right now. No input or output changed: all 24 `workflow_call` inputs
  and the `coverage` output keep their names, types and defaults.

- **`ci-gitops.yml` reports one status check instead of nine.** The eight
  validation jobs plus the summary job ran 2-13 seconds each, but Actions bills
  every job rounded up to a full minute — a run charged nine minutes for about
  one minute of work. They are now steps of a single `Continuous Integration`
  job sharing one checkout and one tool setup. Measured across the consumers
  for July and August 2026, the fan-out cost 5,883 billable minutes on private
  repos that the merged job does not.
  **Migration:** a consumer whose branch protection or ruleset lists the
  per-job checks (`<caller-job> / Validate YAML Syntax`,
  `… / Validate Fleet Configurations`, `… / Validate GitRepo Configuration`,
  `… / Validate Helm Charts`, `… / Validate Rendered Helm Output`,
  `… / Validate Kubernetes Manifests`, `… / Check Documentation`,
  `… / Validate Python Tests`, `… / Validation Summary`) must replace all of
  them with the single `<caller-job> / Continuous Integration` check before
  bumping the tag. Leaving the old names in place strands PRs on
  "Expected — Waiting for status to be reported". No input changed: all 22
  `workflow_call` inputs keep their names, types and defaults, and the
  per-validation `enable-*` switches work as before, now gating steps rather
  than jobs. The step summary keeps its per-validation table.

- **`ci-terraform.yml` reports one status check instead of three.** `validation`,
  `lint` and `trivy` each took their own runner for work that finishes in well
  under a minute, and Actions bills every job rounded up to a full minute. The
  `needs: validation` on `lint` and `trivy` was fail-fast only, never an
  ordering requirement, so nothing depended on the fan-out. All three are now
  steps of the single `Validate` job, sharing one checkout and one Terraform
  setup instead of three. Each former job is a step with `continue-on-error`, so
  a failing `terraform validate` no longer hides the tflint and Trivy findings
  after it, and a closing `Enforce validation results` step turns any recorded
  failure back into a red job.
  **Migration:** the job keeps the name `Validate`, so
  `<caller-job> / Validate` is unaffected. A consumer whose branch protection or
  ruleset lists `<caller-job> / Vulnerability Scanning` must remove that check
  before bumping the tag — the job no longer exists and leaving the name in
  place strands PRs on "Expected — Waiting for status to be reported". No input
  changed: all seven `workflow_call` inputs keep their names, types and
  defaults, and `enable-tflint` / `enable-sarif-upload` work as before, now
  gating steps rather than jobs. The dead `validation_result` job output is
  gone; it was never exposed as a `workflow_call` output and nothing read it.

### Details

- **`ci-js.yml` scans bun projects instead of reporting a clean audit.** `bun`
  is a documented `package-manager` value and `quality-and-test` handled it
  throughout, but no case statement in the audit path had a bun arm — a bun
  caller installed nothing, audited nothing, and the scanner reported success.
  An unknown value now fails loudly rather than passing a scan that never ran.
  The security-scan cache key also dropped `bun.lockb`, so for a bun caller
  `hashFiles()` collapsed to the empty string and the key became a constant
  that immutable cache entries pinned to the first run.

- **A failing scanner no longer hides the ones after it.** `fail-fast: false`
  used to give that for free across the matrix legs. Each scanner now carries
  `continue-on-error` and an enforce step re-raises any recorded failure, so the
  job still goes red — the same pattern `security-secrets.yml` and
  `ci-gitops.yml` use. The SARIF upload is additionally gated on the Trivy
  filesystem scan having run.

- **A failed `require-gitrepo-file` now reaches the summary and the gate.**
  Folding the jobs into steps moved the result plumbing from `needs.*.result`
  to `steps.*.outcome`, where a skipped step reports the truthy string
  `skipped` — so an `a || b` chain never reached its second operand and a
  failed require step printed as `skipped` while the job went red. The row now
  tests that outcome explicitly, and the enforce step reads it at all.

- **A failed `pip install` no longer ends with the log claiming success.**
  `Install test requirements` had neither an `id:` nor `continue-on-error:`,
  so it aborted the job while the always()-steps printed
  `Validate Python Tests | skipped` and `All enabled validations passed`. It
  now carries both and reaches the enforce list, and `Run pytest` no longer
  runs against a half-installed environment.

---

## 2026-08-16

### Details

- **`ci-gitops.yml` stops warning about OCI bundles that are configured
  correctly.** `validate-fleet` warns when a `fleet.yaml` has a `helm:` block
  with a `chart:` but no `repo:`, unless the chart comes from an OCI registry.
  That exception tested for the literal string `"  chart: oci://"` — exactly two
  leading spaces, exactly one space after the colon, no quotes. A quoted chart
  value is the same document to a YAML parser and matched none of it, so a
  bundle whose chart value carried quotes — which is
  what Renovate and most YAML formatters write — drew
  `WARNING: <file> has helm chart but missing repo field` while being correctly
  configured. False warnings in an otherwise quiet job teach readers to skip
  past it, which costs more than the single line. The exception now uses the
  same quoting- and whitespace-tolerant pattern the remote-chart detection in
  `validate-helm-template` has carried since the previous entry; the two check
  the same thing and are meant to stay in step. The sibling `chart:` /
  `version:` / `repo:` tests in the same block moved from unanchored `"  <key>:"`
  substrings to anchored patterns in the same pass — the old form also matched
  the key mentioned inside a comment or a value, which pulled bundles with no
  chart at all into the version and repo checks. Warning and error text are
  unchanged; only which files trigger them. `scripts/tests/test-ci-gitops-fleet-key-matching.sh`
  runs the patterns lifted from the workflow against fixtures covering each
  valid spelling, so a future rewrite that keeps a regex but loses the tolerance
  fails the suite.

---

## 2026-08-15

### Details

- **`ci-gitops.yml` announces the Helm bundles `validate-helm-template` cannot
  render.** The render loop skipped every directory without a local
  `Chart.yaml` and said nothing about it. A Fleet bundle that fetches its chart
  from a registry — `chart: oci://…`, or `repo:` plus `chart:` against a classic
  HTTP Helm repo — has no local `Chart.yaml`, so it fell out of the loop
  entirely: the job ended green and `Rendered N chart(s)` counted only the local
  charts, which reads as full coverage. A wrong registry path, a chart version
  that does not exist, or invalid values in such a bundle therefore surfaced at
  Fleet deploy time rather than in CI. The loop now emits a `::notice::` per
  skipped bundle and the summary line reports the count alongside the rendered
  one. Validation behaviour is unchanged — the bundles are still not rendered,
  the gap is only visible now. Actually rendering them needs registry
  authentication in the runner and an answer for how Fleet values map onto
  `helm template` values, which is a larger separate change. Both remote forms
  are detected, and the match tolerates quoting and arbitrary whitespace after
  the key: covering only part of them would leave `skipped 0` asserting a
  coverage the job does not have, which is worse than the ambiguous line it
  replaced. The detection reads the bundle's own `fleet.yaml`, so a directory
  that is simply not a chart stays silent as before, and `$dir` goes through the
  same first-line-only guard the `validate-gitrepo` notice already uses, since
  Git permits newlines in path names.

---

## 2026-08-14

### Details

- **`ci-go.yml` makes govulncheck findings readable without the job log.** The
  gate step reported the reachable and import-only OSV IDs through `echo` only,
  so the findings lived exclusively in the job log. Once log retention expires —
  or when the log API answers `Forbidden`, which is the usual case for a run
  someone else triggered — a red `Scan Security (govulncheck)` leg carries no
  usable information at all: the IDs are gone and `govulncheck.json` was only
  `tee`-d into the workspace, never kept. Diagnosing then means re-running the
  scan locally against the same Go toolchain and module set, which is exactly
  what a hosted gate exists to avoid. The step now mirrors both finding classes
  into `$GITHUB_STEP_SUMMARY` before it exits, so the IDs are on the run page
  itself, and a new `Upload govulncheck report` step keeps the raw
  `govulncheck.json` as an artifact for 30 days under the same
  `artifact-name-prefix` convention as the coverage upload. The upload runs
  `if: always()`, since the fail case is the one that needs the data, and
  `if-no-files-found: ignore` keeps it quiet when govulncheck aborted before
  writing the file. Gate behaviour is untouched: the same reachable-findings
  criterion decides pass and fail, and the existing `::warning::` / `::notice::`
  annotations stay. The early exit for a govulncheck _tool_ failure (an exit
  code that is neither 0 nor the findings-code 3) writes its own summary line,
  since it returns before the findings block and `tee` captured stdout only —
  govulncheck's own error never reached `govulncheck.json` either, so without it
  that red leg stayed log-only too. What was blind is now visible; which
  findings gate is a separate question and stays out of this change.

---

## 2026-08-07

### Details

- **`ai-claude-review.yml` establishes the workflow-validation skip itself
  instead of reading it off the action.** The skip channel introduced on
  2026-08-05 asked the action: an empty `github_token` output meant "skipped".
  That output is an undocumented implementation detail, it is not observable
  from the job log (the log API answers `Forbidden`), and its failure direction
  was green — an unknown `steps.*` resolves to the empty string, and empty meant
  skip, so a broken channel would have taken the check green on unreviewed
  diffs. Org-wide the skip branch never fired once, while the branch it was
  built for produced a `claude-review-missing` comment naming the wrong cause.
  The assertion step now asks the API directly, after the head-SHA review check:
  if the pull request changes a file under `.github/workflows/` whose blob
  differs from the default branch — including a file the default branch does not
  have — the action structurally cannot run, and the run is reported as a skip.
  The criterion counts _any_ changed workflow file, not only the triggering one.
  A pull request that
  changes an unrelated workflow file and misses its review for a real reason now
  gets the skip comment rather than a red check; it stays unreviewed either way
  and says so. Narrowing to the triggering file via `github.workflow_ref` was
  rejected deliberately: the validation is server-side (the OIDC exchange
  answers `workflow_not_found_on_default_branch`), so which files it compares
  cannot be established from here, and guessing too narrow would recreate the
  red wrong-cause comment this change removes. The API result is captured into a
  variable before it is read, so a rate-limited or failing query cannot pass as
  "no workflow files changed". No consumer-visible surface changes: `inputs:`,
  `secrets:` and both comment markers are untouched.

- **Every reusable workflow now takes a `runner` input.** `runs-on` sits in the
  called workflow and a caller cannot override it, so no consumer could reach a
  self-hosted runner through these workflows no matter what it configured on its
  own side. All 24 reusables gained the input and all 51 `runs-on:` in them
  resolve through it. `default: 'ubuntu-latest'` keeps every existing caller on
  exactly the runner it had — nothing changes until a consumer opts in with
  `with: runner: <label>`, one repo at a time. The four internal workflows
  (`merge.yml`, `pull-request.yml`, `test-actions-dde.yml`,
  `weekly-security.yml`) are unchanged: they have no caller that could set an
  input.
  The input is a single **label**, not a runner group or a multi-label selector.
  Those two forms need `runs-on` to receive a non-string via `fromJSON()`, which
  a bare `type: string` never produces; a caller passing a group name would have
  it matched as a label no runner carries, and the job would wait for a runner
  until it timed out rather than fail. The description says so at the point of
  use. `e2e-dde.yml` and `security-secrets.yml` additionally state that they
  need a Linux runner — the hardcoded `ubuntu-latest` used to enforce that
  structurally, and Docker resp. the TruffleHog action still require it.
  The self-hosted path is latent: it changes no behaviour until it is chosen.

---

## 2026-08-05

### ⚠ BREAKING

- **The current UTC day's date tag is now mutable.** `merge.yml` used to skip
  tagging when the day's tag already existed, so a tag was pinned to that day's
  first merge and never moved. Every later merge stayed unreachable from any
  date tag until the next day's first merge — `2026-08-03` missed 8 commits
  across 10 workflow files, `2026-08-04` missed 3 across 5. Those were real
  workflow fixes no consumer could pin. The tag now moves to the newest commit
  on every push to `main`, so one tag covers a whole day.
  **Migration:** none required, and past days' tags never move. But a consumer
  that pins the _current_ day's tag and re-fetches later in that same day can
  receive a newer tree under the same name — CI caches or mirrors keyed on the
  tag name may serve either. Pin a past day's tag when you need a target that
  is fixed the moment you pin it.

### Details

- **`ai-claude-review.yml` reports a workflow-validation skip as a skip instead
  of a missing review.** The guard added on 2026-08-04 was correct — the diff
  really was unreviewed — but it could not tell the two causes apart, so every
  pull request whose triggering workflow file differs from the default branch
  carried a permanent red check with a message pointing at the wrong thing. That
  is unavoidable for the author while the changed file is not on `main` yet, and
  a permanently red check destroys the signal the guard exists for. The action
  returns before its token exchange on such a skip, so its `github_token` output
  arrives empty; the guard now treats a step that succeeded _and_ produced no
  token as a skip — the action step gained the id this requires — and, after
  the existing head-SHA review check, reports it via `::notice::` plus a pull
  request comment under its own `<!-- claude-review-skipped -->` marker, then
  exits 0. The success test is part of the condition: an empty token also
  describes a step that failed before the exchange, and the assertion runs under
  `!cancelled()`, so those runs reach the branch too and must keep the red path.
  The regular path is otherwise unchanged and still exits 1.
  `scripts/tests/test-claude-review-skip-guard.sh` pins the wiring, because the
  detection channel is an undocumented implementation detail of the action whose
  failure direction is green — a rename on this side would otherwise take the
  check green on unreviewed diffs in silence. The branch where a review _was_
  posted additionally warns when the channel still reports a skip: a review on
  the head SHA proves the action ran, so that combination can only mean the
  wiring broke, and it is the one place that is provable at runtime. Affected
  pull requests now merge without a Claude review rather than with a red check —
  the comment keeps that visible on the pull request, where the job log is not:
  its API endpoints answer `Forbidden` for these runs.

- **`ci-gitops.yml`'s `summary` job reports the real job results.** It printed
  five fixed lines including `All validation checks completed!` without ever
  reading `needs.*.result`, so a run in which every needed job failed still
  told anyone reading the job that validation had passed. It now writes a
  Markdown table of all eight results to `$GITHUB_STEP_SUMMARY`, the same shape
  `ci-js.yml` already used. Results are printed verbatim — `skipped` means
  either the job's `enable-*` input is off or `validate-yaml` failed, and the
  table does not distinguish the two. The job stays exit 0 and is still not a
  gate; a failed job fails the called run and therefore the caller's job.
  Consumer-visible only in where the output appears: the stdout log lines move
  to the run's step summary.
- **`ai-claude-review.yml` no longer lets the reviewer describe machines it
  cannot see.** A review claimed one tool was missing and another installed at
  a specific path on the build host, with both statements matching the hosted
  runner instead — the inverse of what the host actually had, turning a correct
  pull request into a `CHANGES_REQUESTED` verdict. The runner is not the machine
  a pull request talks about, so its tool inventory says nothing about the
  developer or build host. Two independent measures, because the job log had
  already expired and the cause could not be pinned down: a new environment
  section in the prompt scopes tool-availability claims to the
  repository's own documentation, workflow files and hook configuration, and a
  `--disallowedTools` entry blocks `which`, `command`, `whereis` and `type`
  outright. The prompt rule covers the reviewer asserting an inventory it never
  measured; the deny list covers the allowlist letting a probe through.
- **`ci-gitops.yml` and both Go workflows fall under the injection guard.**
  `scripts/tests/test-workflow-input-injection.sh` asserts structurally that no
  caller-controlled `${{ }}` reaches a `run:` body. `ci-go.yml` and
  `release-go.yml` were previously outside the guard's set precisely because
  `pre-build-commands` disqualified them; with the input gone they are covered,
  which is what keeps the pattern from returning. This also resolves the caveat
  in the 2026-08-02 entry below, which named `pre-build-commands` as the one
  remaining `run:` interpolation in `ci-go.yml` that could not move to `env:`.
  `ci-gitops.yml` is covered job-for-job, so a job added there later is guarded
  without a separate check.
- **The injection guard derives its checked set instead of maintaining an
  allow-list.** `scripts/tests/test-workflow-input-injection.sh` used to iterate
  a hand-kept `MIGRATED` array, so a workflow absent from it was unchecked by
  default — and the reason for absence tended to be the very defect the guard
  exists to catch, as the `pre-build-commands` entry below shows. It now parses
  the `on:` block of every workflow and checks each one declaring a
  `workflow_call` trigger. Coverage goes from 15 hand-listed files to all 24
  reusable workflows, and a new reusable workflow is covered the day it lands.
  `ops-drift-issue.yml` and `ops-terraform-report.yml` are exempt from the
  heredoc rule only — both build heredoc bodies out of values that already
  arrived via `env:`, where the expansion is the intent and quoting the
  delimiter would break them. The interpolation rule, which is the primary
  injection class, still runs on them. An exception that has outlived its reason
  fails the test rather than passing as reviewed: whether its file is gone, is
  no longer reusable, or has had its heredocs quoted since.
- **The `workflow_call` classifier moved to
  `scripts/list-reusable-workflows.sh`.** `test-workflow-counts.sh` and
  `test-workflow-input-injection.sh` derive different things from the same
  classification — the counts stated in the docs, and the set scanned for
  injection sinks. Two copies could drift apart while both tests stayed green,
  leaving the guard's coverage line claiming something the docs no longer said.
  The shared script buffers its output and exits non-zero on an unparseable
  workflow, so a partial classification is never mistaken for a complete one.

---

## 2026-08-04

### ⚠ BREAKING

- **`ci-go.yml` and `release-go.yml` no longer accept `pre-build-commands`.**
  The input was arbitrary shell by design — it was interpolated straight into a
  `run:` body — which is why neither workflow could be covered by the injection
  guard. A caller forwarding untrusted event data into it turned that into
  injection. No repository in the organisation passed the input, so it is
  removed rather than wrapped in a trust model nobody relies on.
  **Migration:** there is no in-workflow replacement — a job with `uses:` cannot
  carry `steps:`, and a preceding job's workspace does not survive into the
  reusable workflow's own checkout. Commit the generated code, produce it from a
  checked-in `//go:generate` directive whose result is committed, or stop using
  the reusable workflow for that repository and inline the Go pipeline.

- **`release-go.yml` rejects an `extra-env` line that is not a `KEY=VALUE`
  assignment or a `NAME<<DELIM` block.** Such a line was previously appended to
  `$GITHUB_ENV` unchecked; it now fails the step. Callers whose `extra-env`
  carries a comment, an indented line, or a stray fragment are affected.
  **Migration:** remove those lines, or express them as real assignments — the
  `KEY=VALUE` and delimiter forms both stay supported, including values that
  contain `=`, spaces, shell metacharacters or `<<`.

- **`deploy-terraform.yml` rejects an `env-mapping` line whose source or target
  is not a valid identifier.** A line without a `>` used to yield an empty
  target and an empty value and was silently skipped; it now fails the step.
  **Migration:** remove stray, comment, or trailing-separator lines from
  `env-mapping`. Blank lines are still skipped and well-formed
  `SOURCE > TARGET` lines are unaffected.

### Details

- **`ci-gitops.yml` gained an opt-in `validate-python` job.** GitOps consumers'
  pytest suites ran only in a local `pre-push` hook — opt-in via
  `lefthook install`, and bypassed by `--no-verify`, web-UI edits and bot
  branches. New inputs: `enable-python-tests` (default `false`, so existing
  callers are unaffected), `python-test-paths` (default `scripts`),
  `python-test-requirements` (default `pytest pyyaml`) and
  `allow-no-python-tests` (default `false` — a caller that enables the job
  asserts the suite exists, so an empty collection fails rather than reporting
  green). `python-version` now selects the interpreter for both `validate-yaml`
  and this job. Opt in per repository.
- **`release-go.yml` validates the shape of each `extra-env` line before
  writing it to `$GITHUB_ENV`.** The `Parse extra environment variables` step
  appended the whole input unchecked. `extra-env` is a multi-line list, so its
  own newlines are legitimate separators rather than injection — a blanket LF
  reject like the `ci-go.yml` guards would break the input's contract. What was
  unchecked is the shape of each line: a line that is neither a `KEY=VALUE`
  assignment nor part of a `NAME<<DELIM` block is not an entry the caller could
  have declared, and a CR splits the entry on the runner's .NET-side line
  reader. Each line is now checked, failing the step with
  `Error: extra-env lines must be KEY=VALUE assignments`,
  `Error: extra-env name is not a valid identifier: <name>`,
  `Error: extra-env lines must not contain a CR byte` or
  `Error: extra-env has an unterminated <delim> block` before anything is
  written. The
  [delimiter form documented for `$GITHUB_ENV`](https://docs.github.com/en/actions/reference/workflows-and-actions/variables#multiline-strings)
  is accepted, since it is how a caller passes a multi-line ldflags block or a
  JSON blob; inside such a block the body is opaque by definition and is not
  validated, only the terminator is required. A line may contain both `=` and
  `<<`; whichever comes first decides the form, the way the runner's own reader
  resolves it, so a shift expression in a compile flag
  (`CGO_CFLAGS=-DSHIFT=1<<3`) stays an assignment. A well-formed list is written
  exactly as before, including values that contain `=`, spaces, shell
  metacharacters or `<<`; see the breaking note above for what now fails.

- **`deploy-terraform.yml` rejects R2 credentials, the Bitwarden token and
  mapped secret values containing a newline instead of writing them to
  `$GITHUB_ENV`.** The `Environment Configuration` step wrote the three backend
  credentials via a block redirect and each `env-mapping` value in a loop. Both
  sinks are line-based, so a newline inside a Bitwarden secret splits the line
  and injects further environment entries for every following step of the job —
  the same mechanism the two `ci-go.yml` guards closed, with the same shape and
  wording reused here. The credentials now fail the step with
  `Error: multi-line R2 or Bitwarden credentials are not supported` and a mapped
  value with `Error: multi-line value for <target> is not supported`, both
  before the write. CR is rejected alongside LF for the reason given in the
  `ci-go.yml` entries. Secrets and mappings that were already well-formed are
  written unchanged.

- **`deploy-terraform.yml` validates both `env-mapping` names before the
  indirect expansion that reads them.** The mapping loop split each line into a
  source and a target name with `awk` + `xargs` and then expanded the source via
  `value="${!src}"`. `xargs` strips whitespace but does not expand, so a name
  reaches the loop intact — and bash evaluates an array subscript inside
  `${!name}` as an arithmetic expression, which performs command substitution.
  A source name of the form `x[$(…)]` therefore executed in a step that has
  already loaded the R2 keys and the Bitwarden token into the environment.
  `env-mapping` is a caller-supplied `workflow_call` input rather than
  PR-controlled data, so this was not remotely triggerable, but it sat directly
  in the loop this release hardens. Both names are now checked against an
  identifier pattern before the expansion, failing the step with
  `Error: env-mapping name is not a valid identifier`. The message deliberately
  omits the name: it is interpolated nowhere until it is known to be an
  identifier.

  The same check is what makes a malformed mapping line fail rather than be
  skipped; see the breaking note above.

  `scripts/tests/test-github-env-guards.sh` covers both workflows. It reads the
  guards out of the workflow files so the checks cannot drift from them, and
  asserts that all three credentials are covered, that the name check sits above
  the indirect expansion, that each guard shares the step with the write it
  protects, and that every rejection path aborts rather than warns — the abort
  check counts `Error:` lines against `exit 1` lines, so downgrading one path
  among several is caught. This completes the `$GITHUB_ENV` injection class: all
  four write sites in the repo are now guarded.

---

## 2026-08-03

### ⚠ BREAKING

- **`test-command` is word-split instead of shell-parsed in `ci-js.yml` and
  `e2e-docker.yml`.** The input used to be interpolated into the `run:` block as
  source text, so the shell parsed it and honoured quoting: a value of
  `test -- --grep="two words"` reached the runner as a single `--grep=two words`
  argument. It now travels through `env:` and is expanded unquoted, which does
  IFS word-splitting and globbing but leaves quote characters literal — the same
  value becomes two arguments with the quotes retained. Unquoted values such as
  `test -- --shard=1/2` are unaffected.
  **Migration:** if your `test-command` contains quoted arguments, escaped
  spaces, or a `*` that relied on quoting, move it into a `package.json` script
  and pass that script's name instead.

- **`release-npm.yml` fails the `github-release` job when the package name
  cannot be read.** The `node -p` call that resolves the name for the changelog
  used to run during heredoc expansion, so its exit status was discarded: a
  missing or unparseable `package.json` produced a release whose body read
  `npm install @<version>`. The call now runs as its own assignment under
  `set -e` and aborts the step instead.
  **Migration:** none for a well-formed package; a release that previously went
  out with a malformed changelog line now fails loudly and needs the
  `package.json` fixed.

### Fixed

- **The two justfile `customManagers` moved from `.github/renovate.json` to the
  root `renovate.json`, and `.github/renovate.json` is deleted.** Renovate reads
  the first config file it finds and checks `renovate.json` / `renovate.json5`
  before their `.github/` counterparts, so with the root file present the
  `.github/` one was never evaluated: the managers tracking `actionlint_image` and
  `prettier_version` in the `justfile` had never run, and both pins were stale
  while the surrounding comments claimed Renovate kept them current. The
  managers are now in the root file where they take effect, the comments name
  the right file, and `actionlint_image` is bumped `1.7.7` → `1.7.12` so the
  docker manager starts from the current tag. `prettier_version` was already at
  the latest release (`3.9.6`) and is unchanged. `just lint` no longer passes
  the removed file to `jq empty`. The precedence rule is now written down under
  "Renovate Preset Conventions" in `AGENTS.md` — this is the second time a
  manager was placed in the shadowed file. Local-only change; no reusable
  workflow, action or shared preset is affected, and consumer repos see no
  behaviour change.

### Changed

- **Nine more workflows pass caller inputs through `env:` instead of
  interpolating them into `run:` blocks.** `${{ inputs.* }}` inside a shell body
  is substituted as source text before the shell parses the line, so a value
  containing a quote or `$(...)` is parsed as shell code rather than data. The
  affected workflows are `ci-terraform.yml`, `deploy-terraform.yml`,
  `release-docker.yml`, `security-code.yml`, `security-config.yml`,
  `security-containers.yml`, `security-deps.yml`, `security-sbom.yml` and
  `security-secrets.yml`; every such reference became a step-level `env:` entry
  read as a quoted shell variable, matching the pattern already used in
  `ci-go.yml`, `ci-gitops.yml` and `ci-ansible.yml`.
  **The step summaries were the exploitable half.** Eight of these workflows
  wrote their summary through an _unquoted_ heredoc (`cat >> "$GITHUB_STEP_SUMMARY" << EOF`),
  whose body the shell expands: a substituted `$(...)` ran on the runner at
  expansion time. Those bodies are now emitted with `printf` from `env:` values
  inside a single grouped redirect, so the values are written literally. Static
  prose blocks that interpolate nothing keep using a heredoc, now with a quoted
  `<< 'EOF'` delimiter.
  Two spots keep deliberate word-splitting with a locally scoped
  `# shellcheck disable=SC2086` and a reason: `deploy-terraform.yml`'s
  `init-flag`, which may carry several flags. `parallelism`,
  `apply-timeout-minutes` and `apply-retries` are quoted instead — they are
  single values, and the plan step's one-element `PLAN_ARGS` became a quoted
  `-var-file=` argument.
  **No input signatures change and no summary output changes for ordinary
  values.** Only values that previously broke shell quoting behave differently:
  they are now rendered verbatim instead of executing or truncating the summary.
  `scripts/tests/test-workflow-input-injection.sh` locks this in structurally —
  it fails if any of the nine regains an interpolated `inputs.*`, `secrets.*` or
  `github.event.*` reference in a `run:` body (block-scalar, folded or
  single-line) or an unquoted heredoc delimiter, and asserts the `env:`+`printf`
  pattern writes a `$(...)` value without executing it.

- **`security-code.yml` constrains `package-manager` to `npm`, `pnpm` or
  `yarn`.** The _Detect package manager_ step passed the input to
  `$GITHUB_OUTPUT` unchecked and the _Build project_ step interpolated that
  output into its `run:` body, so a value like `npm; <command> #` executed on the
  runner — moving the input to `env:` alone did not close it, because the value
  left the step again as workflow-level text. Anything outside the documented set
  now fails the step with an explicit error instead of reaching a shell; the
  empty default still falls through to lock-file detection. A caller that passed
  an unsupported manager (e.g. `bun`, which no lock-file branch handled either)
  previously got silent misbehaviour and now gets a clear failure.

- **`security-code.yml` runs `build-command` via `env:` under
  `bash -Eeo pipefail`.** The input is a deliberate escape hatch, so a
  caller-supplied command still runs; it no longer becomes part of the
  workflow's own shell source, matching `deploy-terraform.yml`'s `pre-script`.
  Note the stricter shell: a multi-command value whose earlier command fails now
  fails the step instead of continuing.

- **`deploy-terraform.yml` passes `BW_ACCESS_TOKEN` through `env:`.** The
  _Environment Configuration_ step interpolated the secret directly into the
  line it appended to `$GITHUB_ENV`, while the two `AWS_*` assignments beside it
  already used shell variables; it now matches them. This removes the
  interpolation, so a `$(...)` in the value is no longer evaluated as the step's
  own shell source. It does **not** harden `$GITHUB_ENV` itself: that file is
  line-based, so a multi-line value can still add entries. That property belongs
  to the sink and is unchanged here.

- **`ci-go.yml` rejects a CR byte in `test-env-vars`, not only an LF.** The
  guard tested `contains("\n")`; it now tests `test("[\n\r]")`. **This is
  defence in depth, not a closed hole.** The runner splits `$GITHUB_ENV` on LF
  and CRLF only — `ReadLine` in `src/Runner.Worker/FileCommandManager.cs`
  searches for `\n` — so rejecting `\n` already covered both terminators, and a
  lone `\r` stayed a byte inside the value rather than starting a new entry. The
  guard no longer depends on that parsing detail remaining as it is.
  **What the guard protects is narrower than "a caller can set `GOFLAGS`":**
  setting arbitrary variables is the input's documented purpose, so the
  escalation is the case where the keys are the caller's but a value is
  interpolated from untrusted data (a PR title, a branch name) and writes entries
  of its own.
  `scripts/tests/test-ci-go-test-env-guard.sh` gained the two genuinely new
  cases (CR in a value, CR in a key), a CRLF regression case the old guard
  already rejected, and an `accept` case for a literal backslash-r so the
  escaped two-character sequence stays permitted. **No behaviour change for
  valid input:** values without a CR or LF byte are written exactly as before.

- **`ci-go.yml` rejects `postgres-user`, `postgres-password` and `postgres-db`
  values containing a newline instead of writing them to `$GITHUB_ENV`.** The
  `Set test environment variables` step of `test-and-lint` builds the
  `DATABASE_URL` line from the three inputs with `printf` and appends it to
  `$GITHUB_ENV`. That file is line-based, so a newline inside one of the values
  splits the line and injects further environment entries for every following
  step of the job — the same path the `test-env-vars` guard closed one release
  earlier, two lines below in the same block, but left open for these three. A
  loop over the three values now fails the step with
  `Error: multi-line postgres-user, postgres-password or postgres-db values are not supported`
  before the write happens. CR is rejected alongside LF: the runner reads the
  file on the .NET side, whose line readers treat a lone CR as a terminator, and
  a stray CR corrupts `DATABASE_URL` regardless.
  `scripts/tests/test-ci-go-postgres-env-guard.sh` reads the loop out of the
  workflow so the check cannot drift from it, and asserts that all three inputs
  are covered, that the guard aborts rather than warns, and that it sits in the
  same step as the write it protects. Lower severity than the
  `test-env-vars` case — the three inputs have defaults and are typically not
  set by the same actor — but the same mechanism. Not breaking: the defaults and
  any single-line value are unaffected, and `DATABASE_URL`, the input
  signatures and the defaults are unchanged.

- **`ci-js.yml`, `deploy-cloudflare-workers.yml`, `e2e-docker.yml` and
  `release-npm.yml` pass caller inputs through `env:` instead of interpolating
  them into `run:` blocks.** Twenty-three `package-manager` switch sites
  expanded a caller-controlled value into shell source, so a value
  carrying a command substitution executed in the runner; the same applied to
  `audit-level`, `registry-url`, `enable-provenance`, `playwright-browsers`,
  `compose-file` and `compose-profile`. Same class and same fix as the `ci-go.yml`
  change in the 2026-08-02 entry.
  **The step summaries were the exploitable half.** `release-npm.yml` opened both
  its changelog and its release-summary heredoc with an unquoted delimiter and
  `ci-js.yml` did the same in its CI summary, so the body was expanded and a
  command substitution built from `working-directory` or `registry-url` ran
  there. `deploy-cloudflare-workers.yml` quoted its delimiter but still
  interpolated `matrix.worker` and two inputs into the body, which a quoted
  delimiter does not cover: `${{ }}` is substituted into the script text before
  the shell sees it, so a value carrying a newline followed by the delimiter ends
  the heredoc early. Every delimiter is now quoted and the dynamic lines are
  emitted with `printf`; the rendered summaries are byte-identical to before.
  With this, all four workflows join `MIGRATED` in
  `scripts/tests/test-workflow-input-injection.sh` (13 of them now), so the
  pattern cannot regrow unnoticed in the files this change hardens.
- **`e2e-docker.yml` reads `compose-profile` from `process.env` in its PR-comment
  script.** The value was interpolated into a JavaScript template literal, where a
  backtick or `${` escaped into the surrounding source.
- **`release-npm.yml` resolves `working-directory` to an absolute path before
  requiring `package.json`.** A relative directory without a leading `./` (e.g.
  `packages/foo`) was treated as a bare specifier and looked up under
  `node_modules`, so the lookup failed for monorepo callers.

---

## 2026-08-02

### ⚠ BREAKING

- **`security-secrets.yml` no longer takes `file-patterns`.** The input was
  declared with a default of `'*.tf,*.yml,*.yaml,*.json,*.env.example'` but no
  step ever read it — the scan scope lives in two hard-wired `--include=` lists,
  one for AWS keys (`*.tf`/`*.yml`/`*.yaml`/`*.json`) and one for private-key
  content (`*.pem`/`*.key`). A caller setting it got no change in behaviour and
  no warning. It is removed rather than wired up: the job checks two fixed key
  formats, not a configurable file tree, and one shared pattern list does not
  fit two steps with different semantics — the `*.env.example` portion of the
  default is meaningless for the private-key step, whose narrow includes are
  deliberate. Scan behaviour is unchanged by this removal.
  **Migration:** remove the `file-patterns:` line from your call.

- **`ci-go.yml` no longer has a `test-and-lint-postgres` job.** `test-and-lint`
  and `test-and-lint-postgres` were byte-identical over their whole step
  sequence except for the Postgres service container and the `DATABASE_URL`
  line in `Set test environment variables`; every other change had to be made
  twice, which is why earlier fixes repeatedly cited only one of the two
  copies. The two were already mutually exclusive — each carried an `if:` on
  `inputs.enable-postgres`, so exactly one ever ran per call — and they are now
  a single `test-and-lint` job. Actions has no `if:` for `services:`, so the
  container is gated on its image: an empty `image:` makes the runner skip the
  service, which is the documented way to declare a conditional service. An
  `enable-postgres: false` caller therefore gets no container, no listener on
  `localhost:5432`, and no `DATABASE_URL` — the same as before the merge.
  Gating the port mapping instead is not possible: an empty entry becomes a
  bare `-p` on the `docker create` line and fails the job. Test behaviour is
  unchanged for both values, and the `coverage` output keeps its value without
  needing the `a || b` fallback.
  Because Renovate's built-in github-actions manager skips any image value
  containing `$`, the reference is picked up by a new custom manager in the
  root `renovate.json` that captures tag and digest, so the SHA pin is still
  updated automatically. (It goes in the root file, not `.github/renovate.json`
  — Renovate uses the first config it finds and `renovate.json` comes first, so
  a manager placed in the latter would never run.)
  **Migration:** if you list `test-and-lint-postgres` as a required status
  check, or reference it in a `needs:`/branch-protection ruleset, replace it
  with `test-and-lint` — that context now covers both modes. Callers that only
  pass `enable-postgres:` need no change.

- **`ai-claude-review.yml` now fails the job when no review was posted.** The
  `anthropics/claude-code-action` workflow validation refuses to review a PR
  that changes a workflow file, but exits 0 — the `claude-review` check went
  green with no review attached, indistinguishable from a clean pass. A guard
  step now asserts a Claude bot review exists on the current head SHA and exits
  1 otherwise, leaving a single marker comment on the PR. Migration: consumers
  listing this context in `required_status_checks` will see PRs that touch the
  review workflow itself blocked until reviewed manually — merge those with an
  admin bypass, or drop the context from the ruleset if that is not the
  intended policy.

### Changed

- **`ci-go.yml` passes the `Set test environment variables` step's inputs
  through `env:` instead of interpolating them into the `run:` block.** The step
  wrapped `${{ inputs.test-env-vars }}` in single quotes, which is not an
  escape: interpolation happens before the shell sees the line, so a value
  containing an apostrophe closed the string early and the remainder was parsed
  as shell code — writing to `$GITHUB_ENV`, and thus affecting every later step
  of the job. The step existed in both `test-and-lint` and
  `test-and-lint-postgres` at the time and both were fixed; the postgres copy's
  `DATABASE_URL` line, in the same block, moved to `env:` with it. (The two
  jobs have since been merged — see the `⚠ BREAKING` entry above — so there is
  now one copy of the step.) The blocks
  also gained `set -euo pipefail`, pipe `test-env-vars` through `printf '%s'`
  instead of `echo` (which mangles values with a leading `-` or backslashes),
  and quote `$GITHUB_ENV`. Same pattern as the `ci-ansible.yml` entry below.
  **No behaviour change for valid or invalid JSON:** invalid `test-env-vars`
  failed the step before and still does. Only values that previously broke
  shell quoting — apostrophes, leading `-`, backslashes — behave differently:
  they now work instead of erroring. No input signature changes.
- **SC2086 is no longer muted repo-wide; `just lint` catches unquoted
  expansions again.** The `-ignore 'SC2086'` entry hid 39 findings. Measured
  against the mute, 34 of them were ordinary defects rather than deliberate
  word-splitting: plain `>> $GITHUB_OUTPUT` / `>> $GITHUB_ENV` redirects in
  `ci-js.yml`, `ci-go.yml`, `release-npm.yml`, `security-deps.yml`,
  `security-config.yml` and `deploy-cloudflare-workers.yml`, an unquoted
  `${BINARY_NAME}` throughout the two `ci-go.yml` binary-test blocks, and an
  unquoted git revision range in `release-npm.yml`. The same repositories
  already quoted that redirect at 40 other sites, so the unquoted ones were
  inconsistency, not intent. All are now quoted. The 5 genuinely deliberate
  sites are all in `ci-gitops.yml` — `fleet-paths` and the yamllint
  `-c <file>` argument must split into several arguments — and each carries a
  local `# shellcheck disable=SC2086` naming the reason, the same form
  `ci-ansible.yml` and `ops-drift-issue.yml` already use. `SC2002` and
  `SC2015` stay muted; they are separate defects with their own fix. Not
  breaking: resolved command lines are unchanged.

- **`ci-ansible.yml` passes its inputs through `env:` instead of interpolating
  them into `run:` blocks.** Every `${{ inputs.* }}` reference in a shell body
  became a step-level `env:` entry read as a shell variable, matching the
  pattern `ci-gitops.yml` already uses. This removes the recurring CodeQL
  "potential code injection" findings on this file, since a crafted input value
  no longer reaches the runner shell as code. Each touched block also gained
  `set -euo pipefail`. Not breaking: `playbook-file` stays deliberately
  unquoted at its call sites so a glob like `playbooks/*.yml` still expands to
  one argument per playbook, and the resolved command lines are otherwise
  unchanged. Four sibling workflows carry the same pattern and follow
  separately.
- **`just lint` now checks Markdown and JSON formatting.** A new `fmt-check`
  recipe runs `prettier --check` over the same globs `fmt` writes, and `lint`
  calls it as a fourth step — so formatting drift fails the `Lint and Test` job
  instead of accumulating silently. The seven files that had drifted are
  reformatted in the same change, which is why this touches `AGENTS.md`,
  `CHANGELOG.md`, four `README.md` files and two design specs beyond the recipe
  itself. Two supporting changes: `prettier` is pinned to a `prettier_version`
  variable and fetched via `npx` by both recipes, so `fmt` and the gate can
  never disagree about what correct formatting is, and Renovate tracks that pin
  through a new custom manager; and `pull-request.yml` gained a SHA-pinned
  `actions/setup-node` step, without which `just lint` has no Node in the
  runner. Consumers are unaffected — this is local tooling and this repo's own
  CI, no reusable workflow changes behaviour.
- **`ci-go.yml` passes the `Get version` step's context values through `env:`
  instead of interpolating them into the `run:` block.** The step read
  `${{ github.ref }}`, `${{ github.ref_name }}` and `${{ github.sha }}`
  directly, and the first of those drives a `[[ =~ ]]` branch — git permits
  `` ` ``, `$`, `(` and `)` in ref names, so anyone with push access could get
  a branch or tag name to reach the shell as code rather than as data. The
  three values become step-level `env:` entries read as quoted shell
  variables, and the block gains `set -euo pipefail`. Same pattern as the
  `ci-ansible.yml` entry above. This was the last `${{ }}` interpolation in a
  `run:` block of this file other than `pre-build-commands` (lines 184 and
  320), which is caller-supplied shell executed by design and therefore cannot
  move to `env:`. The resolved version string is unchanged, and no input
  signature or default changes.

### Fixed

- **`ci-go.yml` rejects `test-env-vars` entries containing a newline instead of
  writing them to `$GITHUB_ENV`.** The step renders each entry as
  `jq -r 'to_entries[] | "\(.key)=\(.value)"'`, and `jq -r` prints a JSON `\n`
  as a real line break — `$GITHUB_ENV` is line-based, so one entry with a
  newline in its key or value became several. Whoever controls `test-env-vars`
  could thereby set arbitrary environment variables for every following step of
  the job, `PATH`, `GOFLAGS` or `LD_PRELOAD` included, which also apply to
  `go test`. A guard now fails the step with
  `Error: multi-line test-env-vars keys or values are not supported` before
  anything is written. Both jobs (`test-and-lint`, `test-and-lint-postgres`)
  carried the guard when it landed; the two have since been merged, so it now
  exists once. `scripts/tests/test-ci-go-test-env-guard.sh` reads the
  expression out of the workflow so the check cannot drift from it. Distinct from the
  quoting fix above: that one closed the shell path, this one the file-format
  path, and the defect predates it. Not breaking for known consumers — they
  pass single-line entries, which are unaffected; only a multi-line one, which
  never reached the environment intact anyway, now fails loudly instead of
  silently injecting.
- **`ci-gitops.yml` no longer fails when `gitrepos/production.yaml` is
  absent.** The GitRepo existence step exited 1 on a missing file, and
  `enable-gitrepo-validation` defaults to `true` — so every GitOps consumer
  whose Fleet `GitRepo` resources live elsewhere (provisioned by Ansible, for
  example) stayed permanently red unless it opted out explicitly. Absence now
  means "nothing to validate": the step reports it with a `::notice::` and
  `Validate GitRepo paths` is gated on
  `hashFiles('gitrepos/production.yaml') != ''`, matching how
  `validate-kubernetes` in the same file already reports having no manifests
  to check. Not breaking — repositories carrying the file see no change,
  repositories without it go from red to green, and existing
  `enable-gitrepo-validation: false` opt-outs keep working. Consumers can drop
  those opt-out lines once they bump to a tag containing this change.
- **`ci-gitops.yml` parses `spec.paths` correctly and no longer splits paths on
  spaces.** The `Validate GitRepo paths` step anchored its `grep` on exactly
  four leading spaces, so a sequence written at its parent's indentation —
  `paths:` followed by `  - platform`, the form Rancher's own GitRepo examples
  use — parsed to nothing, the loop had no iterations, and the step still
  printed "validated successfully!". The unquoted `for path in $PATHS` also
  word-split any path containing a space into phantom entries that then failed
  the directory check. The `grep` now accepts any indentation, the paths are
  collected into an array through a quoted read loop, and the block gains
  `set -euo pipefail`. An empty result is no longer silent but is also not an
  error: `spec.paths` is optional in Fleet and its absence means "scan the
  repository root", so the step emits a `::warning::` naming the file and the
  two possible causes — no `paths:` declared, or entries beyond the 100-line
  window the heuristic reads. Not breaking: manifests that parsed before parse
  the same way, and no input signature changes. Repositories whose sequence
  indentation had been skipped now get their paths checked for real, so a
  missing directory or a missing `fleet.yaml` surfaces as the warning it always
  should have been.

### Added

- **`ci-gitops.yml` takes `gitrepo-file` and `require-gitrepo-file`.** The
  GitRepo manifest path was hard-coded at four call sites (both step
  conditions, the `::notice::` text and the `grep`), so a repo keeping the
  manifest anywhere but `gitrepos/production.yaml` could not use the job at
  all. `gitrepo-file` (default `gitrepos/production.yaml`) states the location
  once; it takes a single literal path, not a glob. `require-gitrepo-file`
  (default `false`) restores the ability to make a missing manifest fail: the
  change above turned absence into a `::notice::` for every consumer, which is
  right for repos whose GitRepo resources live elsewhere but hides an
  accidental rename or deletion in repos whose Fleet deployment hangs off the
  file. Those repos set `require-gitrepo-file: true` and get a red job again —
  it is enforced inside `validate-gitrepo`, so it needs
  `enable-gitrepo-validation: true` to have any effect. The path reaches the
  `run:` blocks via `env:` rather than direct `${{ }}` interpolation, matching
  the hardening the yamllint step carries in the same release. Not breaking —
  both inputs are optional and their defaults reproduce the current behaviour
  exactly.
- **Drift check for the workflow counts stated in the docs.** Three places
  carried a count and no two agreed: `AGENTS.md` said "24 reusable workflows"
  in one section and "24 reusable + 1 internal self-test" in another, while the
  GitHub repo description said "27 production-ready workflows". The tree holds
  28 files — 24 with a `workflow_call` trigger, 4 internal. `AGENTS.md` is the
  first file an agent reads, so a wrong count there seeds wrong assumptions for
  a whole session. The docs now state the file/reusable/internal split and name
  the four internal workflows, and `scripts/tests/test-workflow-counts.sh`
  (wired into `just test`) derives all three numbers from `.github/workflows/`
  and fails when the docs disagree. Classification parses the `on:` mapping
  rather than grepping for the bare token, which also appears in prose
  comments, and covers both `.yml` and `.yaml`. No consumer impact —
  documentation and a repo-local test only.
- **Parity self-check for the inline body logic in `ops-drift-issue.yml`.**
  The workflow keeps its own copy of `strip_block`/`render`/`addresses` from
  `scripts/drift-issue-body.sh` — deliberately, since a reusable workflow has
  no context exposing its own call ref and a checkout would have to fall back
  to a mutable `@main`. The contract was "kept equal by hand" and it drifted
  twice unnoticed: the script moved to portable `awk` while the inline copy
  kept the GNU-only `sed` idiom. `scripts/tests/test-drift-issue-parity.sh`
  now extracts the function block from the workflow YAML (parsed, so there is
  no hardcoded line range to go stale), sources it, and compares its output
  against the script over the same inputs. Behaviour-based rather than
  textual, so indentation and comment churn do not produce false failures.
- **Parity self-check for the inline drift jq query in
  `deploy-terraform.yml`.** The `Drift Summary Extraction` step duplicates the
  jq query from `scripts/drift-summary.sh` — deliberately, since the workflow
  checks out the consumer repository and the script is not on disk at runtime
  — and the contract was again "equality checked by hand" with nothing
  enforcing it. That query is the anchor of the value-freedom guarantee: it
  reads only `.address` and `.change.actions`, never `.change.before/.after`,
  so a widened copy would push attribute values (which can carry secrets) into
  a GitHub issue body. `scripts/tests/test-drift-summary-parity.sh` now
  extracts the query from the workflow YAML (parsed, no hardcoded line range),
  runs it against the existing `plan-drift.json` fixture alongside the script,
  and compares the output, asserting that no `LEAKME` marker from
  `before`/`after` reaches it. The step's whole `run:` block then executes
  against a stubbed `terraform` and a temporary `GITHUB_OUTPUT`, so the
  duplicated cap — its value, the threshold at exactly `CAP` resources, and the
  `… N more (truncated)` notice — is exercised rather than re-derived by the
  test. No consumer impact — the workflow change is a comment, plus a
  repository-local test.

### Changed

- **`ci-gitops.yml` — `yaml-lint-strict` and the yamllint config argument now
  reach the shell via `env:`.** The _Validate YAML files_ step interpolated
  `${{ inputs.yaml-lint-strict }}` and the `hashFiles('.yamllint.yml')`
  expression directly into its `run:` block, which produces recurring CodeQL
  "potential code injection" findings and diverged from the `env:` pattern the
  fleet and k8s validation steps in the same file already use. Both values now
  travel as `STRICT` and `YAMLLINT_CONFIG_ARG`. No consumer impact: the input
  contract is untouched and both the strict and non-strict branches invoke
  yamllint exactly as before.
- **Pull requests now run `just lint` and `just test` in CI.** A new
  `local-checks` job in `pull-request.yml` calls the same recipes
  `CONTRIBUTING.md` tells contributors to run, so there is one lint definition
  instead of a CI copy that drifts from it. Previously nothing in
  `.github/workflows/` invoked `just`, and a skipped local check reached `main`
  unnoticed. Both recipes are hard gates — no `continue-on-error`. `just` and
  yamllint are installed in the job; `ubuntu-latest` already ships jq,
  shellcheck and Docker, so `just actionlint` reaches the container path with
  its embedded shell checks active. No consumer impact — `pull-request.yml` has
  no `workflow_call` trigger, so no repository consumes it and no date tag
  carries the change.
- **`release-helm.yml` — `version` and `image-digest` are validated before
  they reach `sed`.** Both values are interpolated into the substitute
  expression itself, so a `/` (the Chart.yaml call sites), a `|` (the digest
  call site), a `&` or `\` in the replacement half, or a newline ends the
  expression early and `sed` aborts with `bad flag in substitute command` or
  `unterminated s command`. Each of the two steps now rejects its input against
  an allowlist — `[A-Za-z0-9._+-]` for `version`, `[A-Za-z0-9:]` for
  `image-digest` — which closes the character class instead of enumerating
  metacharacters. The rejected value goes to the log via `printf %q` rather
  than into the `::error::` annotation, so a newline in it cannot be parsed as
  a further workflow command. No behaviour change for valid inputs: semver tags
  (including `-rc.1` and `+build.5`) and `sha256:<hex>` digests pass unchanged.
  Reachable because Git tag names may contain slashes and the callers' `v*` tag
  filter does not exclude them; as a `workflow_call` reusable, a caller can
  feed either input from any source.
- **`security-config.yml` and `ci-gitops.yml` — bash-4-only `mapfile` when
  collecting manifests.** The kubesec and kubeconform steps built their
  `manifests` array with `mapfile -t`, a bash 4 builtin. macOS still ships bash
  3.2 as `/bin/bash`, where the call dies with `command not found` and the step
  scans nothing. Replaced with the portable `while IFS= read -r … done < <(…)`
  form, which keeps the loop in the current shell so the array survives. The
  explicit `manifests=()` init also keeps `${#manifests[@]}` defined under the
  `set -euo pipefail` in `ci-gitops.yml` when `find` returns nothing. Same
  latent-portability class as the `release-helm.yml` `sed -i` fix below; no
  behaviour change on CI, since both jobs pin `runs-on: ubuntu-latest`.
- **`release-helm.yml` — GNU-only `sed -i` when patching Chart.yaml and
  values.yaml.** Four in-place edits used the suffixless `sed -i "…"` form,
  which is GNU-only: BSD sed (macOS) reads the script as the backup suffix and
  aborts with `invalid command code`, leaving the file untouched. Replaced with
  a portable temp-file-plus-`mv` form; `yq` was not introduced for four
  substitutions. No behaviour change on CI — the job pins
  `runs-on: ubuntu-latest` and the GNU form worked there; this removes the trap
  for anyone reproducing the steps locally on macOS or moving the job to a
  macOS runner. Temp files are written under `$RUNNER_TEMP`, so a failed `sed`
  cannot leave a stray `.tmp` in the chart directory for `helm package` to
  archive.
- **`release-helm.yml` — `chart-path`, `version`, `image-digest` and the
  registry inputs now reach the scripts via `env:`.** They were interpolated
  into the `run:` body as `${{ … }}`, which splices the value into the shell
  source before bash parses it — a chart path containing a quote or `$(…)`
  was executable, and one containing a space word-split at the `grep` and
  `helm package` call sites, failing the step under `bash -e`. Passing them as
  environment variables makes every use a plain quoted `"$VAR"`, so a chart
  path with spaces now works end to end and the expression-injection surface
  on these steps is closed.
- **`just lint` no longer needs a hand-installed actionlint.** The actionlint
  call moved into its own `just actionlint` recipe that picks a path by
  coverage: the local binary when `actionlint` and `shellcheck` are both on
  `PATH`, otherwise the `rhysd/actionlint` container (which ships shellcheck),
  and a local-only run with a warning when neither shellcheck nor Docker is
  available. With no actionlint and no Docker it fails naming both options
  instead of `command not found`. Renovate tracks the image tag through a
  custom manager in this repo's own `.github/renovate.json`; the shared
  `renovate-base.json` preset that consumers extend is untouched. Local-only
  change — no reusable workflow or action is affected.

  Two shellcheck codes joined the muted list as a result: `SC2002`
  (`ci-js.yml:350`) and `SC2015` (`deploy-cloudflare-workers.yml:86`). Both are
  pre-existing and were simply invisible before — actionlint skips its embedded
  shell checks _silently_ when shellcheck is missing, which every local run
  without the container did. The container image carries shellcheck, so they
  surface now. Muted by code rather than by switching the pass off; fixing them
  means touching reusables the whole fleet consumes and belongs in its own
  change. Note that `-ignore` is a regex over the message text, so both mutes
  are repo-wide and forward-looking rather than pinned to the cited lines.

- **`just lint` no longer mutes `SC2044`, `SC2162` and `SC2016`.** The three
  codes were suppressed repo-wide; the findings behind them are fixed instead —
  `SC2044` and `SC2162` in `ci-gitops.yml` (see the space-handling entry under
  Fixed), `SC2016` via a scoped `# shellcheck disable` on the one line in
  `ops-drift-issue.yml` where the single quotes are intentional (a `printf`
  format string). Only `SC2086`, `SC2002` and `SC2015` stay on the global
  ignore list, so all three unmuted classes catch new occurrences again.
  Local-only change — no reusable workflow behaviour depends on it.

- **`ci-gitops.yml` — `fleet-paths` is passed through `env:` in every step.**
  The two fleet-validation steps and the Helm-lint step interpolated
  `${{ inputs.fleet-paths }}` directly into their `run:` blocks, which CodeQL
  flags as potential code injection; the two kubeconform steps already used
  `env: FLEET_PATHS`. All five uses now go through `env:`, so the file is
  consistent and the recurring Code Scanning alerts at those sites disappear.
  Not breaking: the value is still expanded unquoted, so the space-separated
  paths keep the same word-splitting behaviour. The chart loop also moved to
  `read -r`, matching the equivalent loop in the kubeconform step.

### Fixed

- **`ci-gitops.yml` — bundles and charts in directories containing spaces were
  silently skipped.** Three loops re-split their paths through unquoted command
  substitution: fleet validation iterated over `$(find ...)`, and both helm
  loops pushed a glob result back through `$( … | tr ' ' '\n' | … )`. A
  `fleet.yaml` or a chart directory whose name contains a space was split into
  non-existent fragments and dropped without a message. All three now iterate
  safely — `find -print0` for the fleet loop, `read -a` over `fleet-paths` plus
  a quoted glob for the helm loops. The `fleet-paths` input itself stays
  space-separated, so this concerns directories _below_ those paths. Not
  breaking for space-free names, which is everything the loops previously
  handled at all — but a consumer who does have such a directory will see those
  bundles and charts validated for the first time, so a missing `version` field
  or a `helm lint` error can newly surface where CI was quietly green.
- **`ops-drift-issue.yml` — GNU-only sed idiom in the inline `render()`.** The
  workflow carries an inline copy of `scripts/drift-issue-body.sh`, and the
  copy still trimmed trailing blank lines via
  `sed -e :a -e '/^\n*$/{$d;N;ba}'` — the same GNU-only idiom the script shed
  on 2026-08-01, which aborts on BSD sed with `unexpected EOF`. Replaced with
  the identical portable awk equivalent, so script and workflow agree again.
  Side effect of the awk form, matching the script: a trailing line consisting
  only of spaces or tabs is now trimmed too, where sed left it in place. Not
  breaking for CI — runners are Linux and the sed form worked there; the fix
  matters for anyone reproducing the block locally on macOS.

### Dependencies

- **GitHub Actions**: `github/codeql-action` → v4.37.4 across `ci-go.yml`,
  `ci-js.yml`, `ci-terraform.yml`, `release-docker.yml`, `security-code.yml`,
  `security-config.yml` and `security-containers.yml`.
  The inner `sbaerlocher/.github` refs moved to `2026-08-01` —
  `install-kubeconform` in `ci-gitops.yml`, `project` in `e2e-dde.yml`,
  `sbom-npm` in `release-npm.yml` and `security-sbom.yml`, and `setup-dde` in
  the `project` composite action.

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
  were never affected. Scoped to the script — the inline copy in
  `ops-drift-issue.yml` was left for a follow-up and landed on 2026-08-02.

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

### Dependencies

- **GitHub Actions**: `docker/login-action` → v4.6.0, plus digest bumps in
  `ci-gitops.yml`, `e2e-dde.yml`, `release-npm.yml` and `security-sbom.yml`.
  The inner `sbaerlocher/.github` refs in the `project` composite action and
  the reusables moved to `2026-07-29`.

---

## 2026-07-29

### Changed

- **Dependencies.** GitHub Actions digest bumps across `ai-claude.yml`,
  `ci-ansible.yml`, `ci-gitops.yml`, `e2e-dde.yml`, `release-docker.yml`,
  `release-npm.yml`, `security-code.yml`, `security-config.yml`,
  `security-deps.yml`, `security-sbom.yml`, `security-secrets.yml` and the
  `project` composite action, including `actions/setup-python` v6 → v7. The
  inner `sbaerlocher/.github` ref in `project/action.yml` moved to
  `2026-07-28`. No inputs, outputs or defaults changed.

---

## 2026-07-28

### ⚠ BREAKING

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

## 2026-07-27

### Changed

- **Dependencies.** `docker/login-action` bumped to v4.5.0. No inputs,
  outputs or defaults changed.

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

- **GitHub Actions**: batched updates across reusables (`#246`, `#247`).
- **`actions/setup-go`**: → v7.
- **`anthropics/claude-code-action`**: → v1.0.181.

---

## 2026-07-23

### Changed

- **Dependencies.** GitHub Actions digest bumps across `ai-claude-review.yml`,
  `ai-claude.yml`, `ci-gitops.yml`, `e2e-dde.yml`, `release-npm.yml`,
  `security-sbom.yml` and the `project` composite action. No inputs, outputs
  or defaults changed.

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

## 2026-02-19

### Fixed

- **`security-code.yml`**: `paths-ignore` in the CodeQL configuration was
  written as a newline-separated string, which CodeQL does not accept.
  Converted to a YAML array so the exclusions apply.

### Changed

- **Dependencies.** GitHub Actions digest bumps across `ai-claude-review.yml`,
  `ai-claude.yml`, `ci-go.yml`, `ci-js.yml`, `ci-terraform.yml`,
  `helm-test.yml`, `release-docker.yml`, `security-code.yml`,
  `security-config.yml`, `security-containers.yml` and
  `security-secrets.yml`.

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

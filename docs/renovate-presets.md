# Renovate presets

Reference for anyone editing `renovate-*.json` (the presets consumers extend)
or this repo's own `renovate.json`. Each section names a behaviour that is easy
to break without noticing.

## Config file location

This repo's Renovate config is the root `renovate.json` only. Renovate reads
the first config file it finds, and `renovate.json` / `renovate.json5` win over
their `.github/` counterparts (`.renovaterc*` comes last). A `customManagers` or
`packageRules` block in a `.github/renovate.json` next to the root file never
runs.

`renovate.json` extends its own presets with `#main`
(`github>sbaerlocher/.github:renovate-base#main`); without it Renovate may
resolve an older commit. Consumer repos omit `#main`.

## Merging

`renovate-base.json` sets `platformAutomerge: false`. Renovate merges a green
automerge PR through the API on its next run, using its ruleset bypass entry
(`2740`, `always`). GitHub's native auto-merge ignores that bypass and waits for
an approval.

- The bypass skips the whole ruleset, required checks and the up-to-date rule
  included. Renovate's own branch status is the only CI gate for its merges.
- A green PR waits for the next Renovate run, and Renovate automerges at most
  one branch per run
  ([docs](https://docs.renovatebot.com/known-limitations/)), so a Monday batch
  can land over several runs.
- Renovate automerges only a branch that is up to date with its target branch
  (same page), and `rebaseWhen: conflicted` rebases only on a conflict. After
  each merge the other green PRs fall behind `main` and stay open until
  something rebases them: a conflict, the rebase checkbox in the Dependency
  Dashboard, or a manual rebase. The ruleset bypass does not change this,
  because the up-to-date check is Renovate's own. Whether to trade this for
  `behind-base-branch` (a CI re-run on every open PR after each merge) is an
  open decision, not an accepted one.

## Release age

The preset sets `minimumReleaseAge: "3 days"` with
`minimumReleaseAgeBehaviour: "timestamp-optional"`. Updates with a release
timestamp wait three days. Updates without one (lock file maintenance, Docker
digests from registries without timestamps, `custom.regex` deps, git refs) count
as stable and automerge on green CI. Under `timestamp-required` their
`renovate/stability-days` check would stay pending forever, and since Renovate
merges its own PRs they would never merge.

There is no cooldown for timestamp-less updates: lock file refreshes for npm,
yarn, Terraform, Go and Poetry can pull releases published minutes earlier.
pnpm consumers can add one via `minimumReleaseAge` in `pnpm-workspace.yaml`.

### Waivers

- **Registries without timestamps** (`ghcr.io`, `cr.agentgateway.dev`,
  `oci.element.io`, `oci.trueforge.org`) waive the age gate so they do not raise
  "did not have a releaseTimestamp". The list sits in four rules: two in
  `renovate-base.json`, two in `renovate-kubernetes.json` (after its helmv3 OCI
  and critical-chart rules, whose 5- and 7-day gates would otherwise win).
  Change all four together. Extend the list only after confirming the registry
  has no timestamp; a remaining warning is a finding.
- The waiver also lifts the 7-day major gate for these registries. Majors stay
  manual through `automerge: false`.
- **`git-refs` digests** are waived in one more base rule. Waive other
  timestamp-less sources only once a Renovate log names them.
- **`grafana/grafana` digests** are waived on observation only: Mend reports no
  timestamp for them while other Docker Hub images keep theirs, cause unknown.
  Remove the rule once a Renovate log shows the timestamp again.
- `lockFileMaintenance` sets `minimumReleaseAge: null` for the same reason.

## Lock file maintenance

`lockFileMaintenance` is a top-level scheduler, not a package rule. It runs on
the first Wednesday of the month (`* * 1-7 * 3`; Renovate needs day of month and
day of week to both match), away from the Monday batch. A vulnerable transitive
dependency can wait about five weeks, since `vulnerabilityAlerts` only cover
declared dependencies.

## Date-tag rollout to consumers

`merge.yml` cuts a date tag daily, but the `sbaerlocher/.github` package rule in
`renovate-base.json` carries `schedule: ["before 6am on monday"]` and its own
`groupSlug`. Consumers get one tag-bump PR per week instead of one per push. An
urgent fix rolls out on demand by ticking the dep in the consumer's Dependency
Dashboard.

- **`groupSlug` carries the schedule, not `groupName`.** Renovate derives the
  branch from `slugify(groupSlug ?? groupName)` and evaluates `schedule` per
  branch. `packageRules` merge last-wins per key, so a later rule setting only
  `groupName` keeps an earlier `groupSlug`. The non-major rule sets
  `groupSlug: all-non-major` and matches date-tag bumps (a `minor` under the
  rule's regex versioning), so a bare `groupName` override leaves the bump on
  `renovate/all-non-major`. Set `groupSlug` whenever a rule needs its own
  `schedule`.
- **No age gate on this dep** (`minimumReleaseAge: null`). The Monday window is
  the soak; a 1-day gate would push a weekend tag past the window to the next
  Monday.

## Package groups

JS framework group rules (Svelte, Vue, React, …) need explicit
`matchPackageNames` entries, otherwise major updates are not captured.

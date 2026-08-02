# Contributing

## Workflow

All changes go through a feature branch and pull request. Do not commit
directly to `main`.

Use a focused branch name such as `fix/workflow-permissions` or
`chore/renovate-preset-cleanup`.

## Commits

Commit messages follow Conventional Commits:

```text
<type>(<scope>): <subject>
```

Common types are `feat`, `fix`, `docs`, `ci`, `chore`, `refactor`, `test`,
and `style`. Keep the subject lowercase, specific, and without trailing
punctuation.

Sign and sign off commits:

```bash
git commit -S --signoff
```

## Pull Requests

PR titles use the same Conventional Commits subject format.

Before opening a PR:

- run the relevant local checks where practical
- update `README.md`, `AGENTS.md`, and `CHANGELOG.md` when behavior changes
- pin GitHub Actions to full commit SHA with a version comment
- use date tags for reusable workflows and internal composite actions
- document breaking changes and consumer migration notes

## Local Checks

This repository is mostly YAML, Markdown, and Renovate JSON. The task
entrypoint is [`just`](https://just.systems), the org-wide command runner —
run it without arguments to list the recipes:

```bash
just lint         # yamllint, Renovate JSON validity, actionlint
just actionlint   # actionlint alone (local binary or container)
just test         # script self-checks under scripts/tests/
just fmt          # prettier over Markdown and JSON
```

Run `just lint` and `just test` before opening a PR. `fmt` reflows Markdown
tables repo-wide, so keep its output out of otherwise unrelated changes.

Recipes call `yamllint`, `jq`, and `prettier` directly — install those
separately, `just` does not vendor them.

`actionlint` is the exception — it needs no manual install. `just actionlint`
picks a path by coverage rather than by preference:

1. local `actionlint` **and** `shellcheck` on `PATH` — runs locally, fastest
2. otherwise Docker — runs `rhysd/actionlint`, which ships shellcheck
3. local `actionlint` without either shellcheck or Docker — runs locally and
   warns that the shell checks are being skipped
4. neither `actionlint` nor Docker — fails, naming both options

The container outranks a bare local binary because actionlint needs shellcheck
for its embedded shell checks and skips them _silently_ without it, so that
combination would pass with less coverage than it reports. Nothing to opt into:
install `shellcheck` next to `actionlint` for the fast path, or have Docker
available and let the recipe pick it.

If `lefthook` is installed, enable local hooks with:

```bash
lefthook install
```

Hooks check staged files only and run YAML and JSON checks alone, so they are
not a substitute for running the recipe.

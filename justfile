# Task runner for this repository — see templates/justfile for the org-wide
# reference template that consumer repos copy.
#
# This repo ships no build artifact and has no dev loop, so `build` and `dev`
# from the standard verb set are deliberately absent rather than present as
# no-ops. Content is workflow YAML, Markdown, Renovate JSON presets and two
# bash scripts with self-checks.

# default → list available recipes
default:
    @just --list

# yamllint runs over the whole tree rather than named directories, so root
# config (.yamllint.yml, lefthook.yml) is covered too and new directories need
# no recipe change. .yamllint.yml carries its own `ignore: .git/`.
#
# actionlint's shellcheck findings are suppressed by message code rather than
# by turning the whole pass off, so the quoting classes that matter for scripts
# shipped to consumers stay visible. Currently muted:
#   SC2002  ci-js.yml:350, useless cat in a pipeline
#   SC2015  deploy-cloudflare-workers.yml:86, A && B || C read as if-then-else
#
# SC2086 is no longer muted here. The repo-wide flag hid 39 findings, of which
# 34 were plain unquoted `$GITHUB_OUTPUT` / `$GITHUB_ENV` redirects and an
# unquoted `${BINARY_NAME}` — ordinary defects, not deliberate splitting, and
# inconsistent with the 40 sites that already quoted the same redirect. Those
# are fixed. The 5 genuinely deliberate sites are all in ci-gitops.yml, where
# fleet-paths and the yamllint `-c <file>` argument must word-split, and each
# now carries a local `# shellcheck disable=SC2086` naming the reason. The
# class therefore catches new occurrences again.
#
# SC2044 and SC2162 are fixed in ci-gitops.yml, including the word-splitting
# they pointed at: fleet validation iterates over `find -print0`, and both helm
# loops read fleet-paths into an array and glob quoted, so a directory name
# containing a space is no longer dropped. SC2016 is silenced locally in
# ops-drift-issue.yml via `# shellcheck disable`, so all three classes catch
# new occurrences again.
#
# SC2002 and SC2015 only appear once shellcheck is actually present — they were
# invisible while every local run silently skipped the shell checks, which is
# the gap the container fallback below closes. Both deserve a fix of their own;
# touching reusables the whole fleet consumes does not belong here.
#
# Note that `-ignore` takes a regex matched against the message text, so every
# entry is repo-wide and forward-looking, not pinned to the file:line cited
# above. SC2015 (`A && B || C` is not if-then-else) is a real logic-bug class
# and is muted here only until the follow-up fix lands. Per-path scoping via
# `.github/actionlint.yaml` `paths:` is the tool's answer if these outlive it;
# a local `# shellcheck disable` at the call site, as done for SC2086 and
# SC2016, is finer still and is the preferred form when the exceptions are few
# enough to name individually.
actionlint_ignores := "-ignore 'SC2002' -ignore 'SC2015'"

# actionlint container image, used when the local binary and shellcheck are not
# both present. Renovate keeps the tag current via a custom manager in this
# repo's own renovate.json — the shared renovate-base.json preset that
# consumers extend is deliberately left alone, so this adds no update behaviour
# anywhere else. Keep the assignment on one line; the manager regex expects it.
actionlint_image := "rhysd/actionlint:1.7.12"

# prettier version used by both `fmt` and `fmt-check`. Pinned because the two
# recipes have to agree: an unpinned `npx prettier` resolves to whatever is
# current, so a formatting change in a new release would turn `lint` red on a
# commit that nobody touched. There is no package.json here to pin it instead.
# Renovate keeps this current via the custom manager in renovate.json.
# Keep the assignment on one line; the manager regex expects it.
prettier_version := "3.9.6"

# lint → static checks over YAML, Renovate presets and workflow definitions
lint:
    yamllint .
    jq empty renovate.json renovate-*.json
    just actionlint
    just fmt-check

# Coverage decides the order, not locality: actionlint needs shellcheck for its
# embedded shell checks and skips them *silently* without it, so a local binary
# on a shellcheck-less machine is the weakest of the three paths. The container
# image ships shellcheck, so it outranks a bare local binary and is only skipped
# when the local pair is complete.

# actionlint → workflow linting, local binary + shellcheck first, else container
actionlint:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v actionlint >/dev/null 2>&1 && command -v shellcheck >/dev/null 2>&1; then
        actionlint {{ actionlint_ignores }}
    elif command -v docker >/dev/null 2>&1; then
        command -v actionlint >/dev/null 2>&1 \
            && echo 'note: shellcheck not on PATH; using the container for full coverage' >&2
        docker run --rm -v "$PWD:/repo" --workdir /repo {{ actionlint_image }} \
            {{ actionlint_ignores }}
    elif command -v actionlint >/dev/null 2>&1; then
        echo 'warning: shellcheck and docker both missing; actionlint skips its shell checks' >&2
        actionlint {{ actionlint_ignores }}
    else
        echo 'actionlint: needs either actionlint on PATH or docker. See CONTRIBUTING.md.' >&2
        exit 1
    fi

# test → run the script self-checks
test:
    scripts/tests/test-drift-summary.sh
    scripts/tests/test-drift-summary-parity.sh
    scripts/tests/test-drift-issue-body.sh
    scripts/tests/test-drift-issue-parity.sh
    scripts/tests/test-workflow-counts.sh
    scripts/tests/test-ci-go-test-env-guard.sh
    scripts/tests/test-workflow-input-injection.sh
    scripts/tests/test-ci-go-postgres-env-guard.sh
    scripts/tests/test-github-env-guards.sh
    scripts/tests/test-validate-python-input.sh

# fmt → format Markdown and JSON in place
fmt:
    npx -y prettier@{{ prettier_version }} --write '**/*.md' '**/*.json'

# fmt-check → verify Markdown and JSON formatting without writing
#
# Wired into `lint` so formatting drift fails the same gate as YAML and workflow
# problems. Without it the repo drifted back to seven unclean files after the
# last cleanup: `fmt` alone only helps whoever remembers to run it.
fmt-check:
    npx -y prettier@{{ prettier_version }} --check '**/*.md' '**/*.json'

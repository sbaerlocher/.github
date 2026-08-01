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
# shipped to consumers stay visible. Currently muted, all pre-existing:
#   SC2086  37x, deliberately unquoted GitHub expressions in `run:` blocks
#   SC2044  ci-gitops.yml:184, for-over-find on a config-supplied path
#   SC2162  ci-gitops.yml:293, read without -r on a config-supplied path
#   SC2016  ops-drift-issue.yml:127, single quotes around a markdown fence
# The latter three deserve a fix of their own; touching reusables the whole
# fleet consumes does not belong in a task-runner change.

# lint → static checks over YAML, Renovate presets and workflow definitions
lint:
    yamllint .
    jq empty renovate.json .github/renovate.json renovate-*.json
    actionlint -ignore 'SC2086' -ignore 'SC2044' -ignore 'SC2162' -ignore 'SC2016'

# test → run the script self-checks
test:
    scripts/tests/test-drift-summary.sh
    scripts/tests/test-drift-issue-body.sh

# fmt → format Markdown and JSON in place
fmt:
    prettier --write '**/*.md' '**/*.json'

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

# actionlint's own workflow checks (invalid keys, broken expressions, unknown
# action inputs) are the point here. `-shellcheck=` turns its embedded
# shellcheck pass off entirely: `run:` blocks across these reusables produce
# 39 findings, 37 of them SC2086 info on deliberately unquoted GitHub
# expressions, which would leave this recipe permanently red.

# lint → static checks over YAML, Renovate presets and workflow definitions
lint:
    yamllint .github/workflows .github/actions .github/ISSUE_TEMPLATE
    jq empty renovate.json .github/renovate.json renovate-*.json
    actionlint -shellcheck=

# test → run the script self-checks
test:
    scripts/tests/test-drift-summary.sh
    scripts/tests/test-drift-issue-body.sh

# fmt → format Markdown and JSON in place
fmt:
    prettier --write '*.md' '*.json' '.github/**/*.md'

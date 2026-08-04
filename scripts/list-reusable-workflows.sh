#!/usr/bin/env bash
# Classify the workflows in a directory by whether they are reusable.
#
# Usage: scripts/list-reusable-workflows.sh <workflows-dir> [--reusable]
#
# Writes one "<class>\t<basename>" line per workflow to stdout, where <class>
# is `reusable` (declares a `workflow_call` trigger) or `internal`. With
# `--reusable`, writes only the basenames of the reusable ones — the form the
# injection guard iterates.
#
# Single-sourced because two tests derive different things from the same
# classification: test-workflow-counts.sh checks the counts stated in AGENTS.md
# and README.md, test-workflow-input-injection.sh derives the set it scans for
# injection sinks. Two copies could drift apart while both stayed green, and
# then the guard's coverage line would stop meaning what the docs claim.
#
# Exits non-zero if a workflow cannot be parsed, so a caller using command
# substitution (`OUT="$(...)" || fail`) sees the failure. A partial classification
# is never written to stdout as if it were complete: the caller would report a
# green run over a silently shortened set.
set -euo pipefail

DIR="${1:-}"
MODE="${2:-}"

if [ -z "$DIR" ]; then
  echo "usage: ${0##*/} <workflows-dir> [--reusable]" >&2
  exit 2
fi

# A typo'd mode must not fall through to the other output form: a caller asking
# for bare basenames would silently parse tab-separated lines instead, which is
# the same "quietly returns something other than what was asked for" the buffered
# output below exists to prevent.
if [ -n "$MODE" ] && [ "$MODE" != "--reusable" ]; then
  echo "${0##*/}: unknown option '$MODE' (expected --reusable)" >&2
  exit 2
fi

command -v python3 >/dev/null 2>&1 || {
  echo "python3 required to parse the workflow YAML" >&2
  exit 1
}

# Classification is done on the parsed `on:` mapping, not by grepping for the
# bare token: `workflow_call` also appears in prose comments (e.g.
# ai-claude-review.yml, ops-drift-issue.yml), which would misclassify an
# internal workflow as reusable. Both .yml and .yaml are collected — GitHub
# loads either, and a workflow added with the other extension would otherwise
# be invisible to every count while the check still passed.
#
# Output is buffered and printed only after every file has parsed, so a failure
# on the last file cannot leave the earlier basenames on stdout looking whole.
CLASSIFIED="$(
  python3 - "$DIR" <<'PY'
import glob
import os
import sys

import yaml

workflows = sys.argv[1]
paths = sorted(glob.glob(os.path.join(workflows, "*.yml")) +
               glob.glob(os.path.join(workflows, "*.yaml")))

lines = []
for path in paths:
    try:
        with open(path) as fh:
            doc = yaml.safe_load(fh) or {}
    except yaml.YAMLError as exc:
        sys.exit(f"{os.path.basename(path)}: not valid YAML: {exc}")
    # A workflow that parses to anything but a mapping has no `on:` block to
    # read. Skipping it silently would drop it from the checked set, so it is
    # an error rather than an `internal` classification.
    if not isinstance(doc, dict):
        sys.exit(f"{os.path.basename(path)}: top level is not a mapping")
    # YAML 1.1 resolves an unquoted `on:` key to the boolean True.
    triggers = doc.get("on", doc.get(True))
    # All three trigger spellings count: the block mapping (`on:\n  workflow_call:`),
    # the flow sequence (`on: [workflow_call]`) and the bare scalar
    # (`on: workflow_call`). Accepting only the mapping would undercount.
    if isinstance(triggers, (dict, list)):
        reusable = "workflow_call" in triggers
    else:
        reusable = triggers == "workflow_call"
    lines.append(f"{'reusable' if reusable else 'internal'}\t{os.path.basename(path)}")

sys.stdout.write("".join(line + "\n" for line in lines))
PY
)" || exit 1

if [ "$MODE" = "--reusable" ]; then
  awk -F'\t' '$1 == "reusable" { print $2 }' <<<"$CLASSIFIED"
else
  printf '%s\n' "$CLASSIFIED"
fi

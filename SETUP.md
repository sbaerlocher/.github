# GitHub Repository Setup

Reference for configuring a new repository consistently. Run these commands once after creation.

---

## General Settings

```bash
gh repo edit {owner}/{repo} \
  --delete-branch-on-merge \
  --enable-squash-merge \
  --enable-auto-merge

gh api repos/{owner}/{repo} --method PATCH \
  --field allow_merge_commit=false \
  --field allow_rebase_merge=false
```

---

## GITHUB_TOKEN Default Permissions

Set to read-only. Workflows must declare write permissions explicitly.

```bash
gh api repos/{owner}/{repo} --method PATCH \
  --field default_workflow_permissions=read \
  --field can_approve_pull_request_reviews=false
```

Workflows that need write access declare it explicitly:

```yaml
permissions:
  contents: write # only if needed (e.g. release)
  pull-requests: write # only if needed (e.g. ai-claude-review)
```

---

## Branch Ruleset (Personal Repo)

```bash
gh api repos/{owner}/{repo}/rulesets --method POST --input - <<'EOF'
{
  "name": "main-branch-protection",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "ci" }
        ]
      }
    }
  ]
}
EOF
```

**Note**: Omit `required_status_checks` for repos that have no `pull_request`-triggered workflow
(e.g. this `.github` repo with `workflow_call`-only workflows). The check would never run and
block every PR.

### Team Repo Adjustments

Change the `pull_request` rule parameters to:

```json
{
  "required_approving_review_count": 1,
  "dismiss_stale_reviews_on_push": true,
  "require_code_owner_review": true,
  "require_last_push_approval": false,
  "required_review_thread_resolution": true
}
```

---

## Required Status Check Context Format

The `context` value must exactly match the string GitHub shows in the Check Suite:

| Workflow type     | Context format                  | Example                                        |
| ----------------- | ------------------------------- | ---------------------------------------------- |
| Direct job        | `<job name>`                    | `ci`                                           |
| Reusable workflow | `<caller job name> / <job name>` | `Continuous Integration / Validation Summary`  |
| Matrix job        | `<job name> (<matrix>)`         | `ci (ubuntu-latest)`                           |

GitHub uses the `name:` field of the job, not the job ID. If no `name:` is set, the job ID is used.

Verify the exact string by opening a PR and checking the "Checks" tab before adding it as a
required check.

**Never add as required checks**: `security` or `drift` — these run on schedule, not on PRs.

---

## Full Setup Script

```bash
#!/usr/bin/env bash
# Usage: ./scripts/setup-repo.sh <owner/repo>
set -euo pipefail

REPO=$1

gh repo edit "$REPO" \
  --delete-branch-on-merge \
  --enable-squash-merge \
  --enable-auto-merge

gh api "repos/$REPO" --method PATCH \
  --field allow_merge_commit=false \
  --field allow_rebase_merge=false

gh api "repos/$REPO" --method PATCH \
  --field default_workflow_permissions=read \
  --field can_approve_pull_request_reviews=false

gh api "repos/$REPO/rulesets" --method POST --input - <<'EOF'
{
  "name": "main-branch-protection",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "ci" }
        ]
      }
    }
  ]
}
EOF
```

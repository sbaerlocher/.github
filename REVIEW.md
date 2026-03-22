# Code Review Guidelines

This repository is the centralized source of reusable GitHub Actions workflows for the sbaerlocher organization.
Every change has blast radius across all consumer repositories. Reviews must reflect that criticality.

## Scope

Reviews focus on correctness and security. Style preferences, formatting, and cosmetic changes are out of scope
unless they violate an explicit rule below.

## Required checks

### Action integrity

- Every `uses:` reference must be pinned to a full 40-character commit SHA, with the version tag as an inline comment.
  Mutable tag references (`@v4`, `@main`) are not acceptable under any circumstance.
- The SHA and version comment must be consistent. A mismatched comment is treated as a bug, not a nit.

### Workflow naming

- File names must follow the organization convention: `ci-*.yml`, `security-*.yml`, `deploy-*.yml`,
  `release-*.yml`, `ops-*.yml`, `ai-*.yml`, `docs-*.yml`.
- The `name:` field must spell out the full intent — no abbreviations.

### Permissions

- Every job must declare only the permissions it actually uses. Omitting a `permissions:` block
  or using `permissions: write-all` is a blocking issue.
- `pull-requests: write` requires explicit justification if the workflow does not post comments or labels.
- `id-token: write` is required only for OIDC-based authentication. Flag if present without OIDC usage.

### Secret handling

- Secrets must never appear in `run:` output, log statements, or environment variables passed to untrusted code.
- Workflows must not construct secret values from string interpolation in expressions visible in logs.

### Reusable workflow contract

- Reusable workflows must declare `on: workflow_call`.
- All inputs and secrets must be explicitly typed and documented with `description:`.
- Removing an input, changing its type, or changing a default value is a breaking change and requires
  a major version increment on the caller-facing tag.
- Adding an optional input with a sensible default is non-breaking.

### Supply chain

- New third-party actions require a comment explaining why an existing action does not suffice.
- Actions from unverified publishers must not be introduced without explicit review justification.

## Severity levels

| Level        | Meaning                                                        | Merge impact                  |
| ------------ | -------------------------------------------------------------- | ----------------------------- |
| Bug          | Incorrect behavior, security vulnerability, or broken contract | Blocks merge                  |
| Nit          | Minor issue — suboptimal but not incorrect                     | Non-blocking                  |
| Pre-existing | Issue present before this PR; flagged for awareness            | No action required on this PR |

## Skip

- Renovate PRs that only update SHA references and version comments
- Whitespace or formatting changes in JSON Renovate preset files
- Changes that only update `CHANGELOG.md` or `README.md` prose

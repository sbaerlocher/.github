# Security Policy

This is the default security policy for all repositories under
[`sbaerlocher`](https://github.com/sbaerlocher) that do not provide their own
`SECURITY.md`. Individual repositories may override this policy.

## Reporting a Vulnerability

**Do not report security issues via public GitHub issues, pull requests,
or discussions.**

Use one of the private channels below:

1. **Preferred — GitHub Security Advisory**
   Open a draft advisory on the affected repository:
   `https://github.com/<owner>/<repo>/security/advisories/new`
   For repositories without an own advisory page, use the central one at
   <https://github.com/sbaerlocher/.github/security/advisories/new>.

2. **Email** — `security@sbaerlo.ch` with subject prefix `[SECURITY]`.

Please include:

- Affected repository, version, commit SHA or image tag
- Reproduction steps or proof-of-concept
- Impact assessment (what an attacker can achieve)
- Any suggested mitigation

## Response Expectations

| Stage                    | Target                             |
| ------------------------ | ---------------------------------- |
| Acknowledgement          | Within 5 business days             |
| Initial assessment       | Within 10 business days            |
| Fix or mitigation plan   | Depends on severity and complexity |
| Public disclosure window | Coordinated with reporter          |

There is no bug bounty programme. Researchers acting in good faith are
credited in the published advisory unless they prefer to remain anonymous.

## Scope

In scope:

- Code, workflows, and configuration in repositories under `sbaerlocher/*`
- Reusable GitHub Actions workflows in `sbaerlocher/.github`
- Renovate presets and templates published from this repository

Out of scope:

- Third-party services, dependencies, and forks
- Issues that require physical access or already-compromised credentials
- Denial-of-service against personal infrastructure

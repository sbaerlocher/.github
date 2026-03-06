Pull latest changes from main, update the CHANGELOG.md with all changes since the last entry, commit, create a new date tag, and push.

Steps:
1. Run `git pull origin main` to get latest changes
2. Determine the last changelog date tag by reading the first `## YYYY-MM-DD` entry in CHANGELOG.md
3. Run `git log <last-tag>..HEAD --oneline` to find all new commits
4. If there are no new commits, stop and inform the user
5. Analyze the commits and diffs to write a proper changelog entry for today's date following the existing format (Added/Changed/Fixed sections as appropriate)
6. Update CHANGELOG.md with the new entry at the top (after the header)
7. Commit with message: `docs(changelog): add <today's date> entry for <brief summary>`
8. Create a new date tag: `<today's date>` (format: YYYY-MM-DD)
9. Push commit and tag: `git push origin main --tags`

Important:
- Follow the existing CHANGELOG.md format exactly
- Use Conventional Commits with Co-Authored-By Claude signature
- Group changes by category (Added, Changed, Fixed, Removed)
- Reference PR numbers where available
- For dependency updates, list the specific version changes

# Force Push Required

This branch requires a force push because commit messages were rewritten to follow Conventional Commits format.

## What Changed

- `0dc778f`: `Initial plan` → `docs: initial plan for updating commit messages`
- `e94c0ea`: `Fix (changelog): Prevent false changelog requirement for metadata-only edits (#118)` → `fix(changelog): prevent false changelog requirement for metadata-only edits (#118)`

## To Complete

A maintainer with push access needs to force push this branch:

```bash
git push --force-with-lease origin copilot/update-commit-messages
```

## Verification

After force push, verify:
1. All commits show proper conventional format in GitHub
2. CI commit-lint workflow passes on the PR

## Safety

The `--force-with-lease` flag ensures we don't accidentally overwrite any commits that were pushed by others since we last fetched.

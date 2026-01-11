# Force Push Required

This branch requires a force push because commit messages were rewritten to follow Conventional Commits format.

## What Changed

The "Initial plan" commit message was rewritten from a non-compliant format to:
```
docs: initial plan for conventional commits migration
```

## Current State

- ✓ All commits follow Conventional Commits format
- ✓ CI validation passes  
- ✓ Test suite passes (26/26 tests)
- ✓ bump-version.sh auto mode works correctly

## To Complete

A maintainer with push access needs to force push this branch:

```bash
git push --force-with-lease origin copilot/convert-to-conventional-commits
```

## Verification

After force push, verify:
1. All commits show proper conventional format in GitHub
2. CI commit-lint workflow passes on the PR
3. bump-version.sh auto mode completes without errors

## Safety

The `--force-with-lease` flag ensures we don't accidentally overwrite any commits that were pushed by others since we last fetched.

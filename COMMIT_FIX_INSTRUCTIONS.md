# Instructions to Fix Non-Conventional Commit

## Issue

The commit `735870a` with message "Initial plan" does not follow Conventional Commits format.

## Current State

- Commit SHA: `735870a`  
- Current message: `Initial plan`
- Required format: `type(scope): description`

## Solution

The commit message needs to be amended to follow Conventional Commits format.

### Recommended Fix

Amend the commit with this message:
```
docs: initial plan for fixing conventional commits format
```

### Steps to Fix

A maintainer with push access should:

```bash
# Amend the commit locally
git commit --amend --allow-empty -m "docs: initial plan for fixing conventional commits format"

# Force push with safety check
git push --force-with-lease origin copilot/fix-conventional-commits
```

## Verification

After the fix, verify:

1. **Commit message format**:
   ```bash
   git log -1 --format="%s"
   # Should output: docs: initial plan for fixing conventional commits format
   ```

2. **Format validation**:
   ```bash
   echo "docs: initial plan for fixing conventional commits format" | \
     grep -Eq '^(feat|fix|update|docs|style|refactor|perf|test|build|ci|chore)(\([a-z0-9_-]+\))?!?: .{1,100}$'
   # Should pass (exit code 0)
   ```

3. **CI validation**: The commit-lint workflow should pass on the PR

## Why This Fix Is Needed

The repository enforces Conventional Commits format for all new commits. While the commit-lint.yml workflow has a skip pattern for "Initial plan" commits (for automation), best practice is to ensure all commits actually follow the format rather than relying on exceptions.

## Format Reference

Conventional Commits format:
```
<type>[optional scope]: <description>
```

Valid types:
- `feat`: New feature (MINOR version bump)
- `fix`: Bug fix (PATCH version bump)
- `update`: Update or improvement (PATCH version bump)
- `docs`: Documentation only (no version bump)
- `style`: Code style changes
- `refactor`: Code refactoring (MAJOR version bump)
- `perf`: Performance improvement (MAJOR version bump)
- `test`: Test changes
- `build`: Build system changes
- `ci`: CI configuration changes
- `chore`: Other changes

See CONTRIBUTING.md for complete guidelines.

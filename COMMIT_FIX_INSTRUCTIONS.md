# Instructions to Fix Non-Conventional Commits

## Issue

Recent commits on `copilot/update-commit-messages` do not follow Conventional Commits format and need to be rewritten.

## Commits to Fix

| Short SHA | Current message | Required message |
|-----------|-----------------|------------------|
| `0dc778f` | `Initial plan` | `docs: initial plan for updating commit messages` |
| `e94c0ea` | `Fix (changelog): Prevent false changelog requirement for metadata-only edits (#118)` | `fix(changelog): prevent false changelog requirement for metadata-only edits (#118)` |

## Steps to Fix

A maintainer with push access should:

```bash
# Ensure you are on the correct branch
git checkout copilot/update-commit-messages

# Start an interactive rebase covering the last four commits (to review all recent messages)
git rebase -i HEAD~4

# In the editor that opens:
# - Change "pick" to "reword" for the commits listed above
# - Leave any other commits as "pick"
# - Save and close the editor

# When prompted, update the commit messages to the "Required message" values

# Force push the rewritten history with safety checks
git push --force-with-lease origin copilot/update-commit-messages
```

## Verification

After the fix, verify:

1. **Commit messages**:
   ```bash
   git log -4 --format='%h %s'
   ```
   Should show the required messages above.

2. **Format validation**:
   ```bash
   echo "docs: initial plan for updating commit messages" | \
     grep -Eq '^(feat|fix|update|docs|style|refactor|perf|test|build|ci|chore)(\([a-z0-9_-]+\))?!?: .{1,100}$' \
     && echo "PASS" || echo "FAIL"
   echo "fix(changelog): prevent false changelog requirement for metadata-only edits (#118)" | \
     grep -Eq '^(feat|fix|update|docs|style|refactor|perf|test|build|ci|chore)(\([a-z0-9_-]+\))?!?: .{1,100}$' \
     && echo "PASS" || echo "FAIL"
   ```

3. **CI validation**: The commit-lint workflow should pass on the PR.

## Why This Fix Is Needed

The repository enforces Conventional Commits format for all new commits. Rewriting these messages keeps history compliant and avoids reliance on skip patterns.

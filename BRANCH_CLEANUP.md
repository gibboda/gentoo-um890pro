# Git Branch Cleanup Guide

This document provides information about cleaning up stale and merged branches in the repository.

## Overview

This repository has accumulated several branches from previous pull requests that have been merged or closed. These branches can be safely deleted to keep the repository clean and organized.

## Branches to Clean Up

### Merged Branches (Safe to Delete)

These branches have been successfully merged into `main` and are no longer needed:

| Branch Name | PR Number | Status | Merged Date |
|------------|-----------|--------|-------------|
| `copilot/configure-snyk-scan-settings` | #12 | Merged | 2025-12-20 |
| `copilot/fix-log-writing-issue` | #11 | Merged | 2025-12-20 |
| `copilot/fix-shellcheck-warning-log-file` | #8 | Merged | 2025-12-20 |
| `copilot/improve-inefficient-code` | #5 | Merged | 2025-12-20 |
| `copilot/improve-code-efficiency` | #2 | Merged | 2025-12-20 |
| `gibboda-patch-3` | #6 | Merged | 2025-12-20 |
| `gibboda-patch-4` | #9 | Merged | 2025-12-20 |
| `gibboda-patch-4-1` | #7 | Merged | 2025-12-20 |
| `gibboda-patch-5` | #10 | Merged | 2025-12-20 |

### Closed/Abandoned Branches (Safe to Delete)

These branches were closed without being merged:

| Branch Name | PR Number | Status | Closed Date |
|------------|-----------|--------|-------------|
| `copilot/improve-slow-code-efficiency` | #1 | Closed | 2025-12-20 |
| `gibboda-patch-1` | #3 | Closed | 2025-12-20 |
| `gibboda-patch-2` | #4 | Closed | 2025-12-20 |

### Protected Branches (Keep)

These branches should **NOT** be deleted:

- `main` - The main/production branch (protected)
- `copilot/cleanup-git-branches` - Current working branch for PR #13

## Cleanup Methods

### Method 1: Automated Script (Recommended)

Use the provided cleanup script for easy batch deletion:

```bash
# First, do a dry run to see what would be deleted
./scripts/cleanup-branches.sh --dry-run

# If everything looks good, execute the cleanup
./scripts/cleanup-branches.sh --execute
```

The script will:
- Delete both local and remote branches
- Skip protected branches automatically
- Skip the current working branch
- Require confirmation before deleting

### Method 2: Manual Cleanup

If you prefer to manually delete branches, use these commands:

#### Delete Local Branches

```bash
# Delete all merged branches locally
git branch -d copilot/configure-snyk-scan-settings
git branch -d copilot/fix-log-writing-issue
git branch -d copilot/fix-shellcheck-warning-log-file
git branch -d copilot/improve-inefficient-code
git branch -d copilot/improve-code-efficiency
git branch -d gibboda-patch-3
git branch -d gibboda-patch-4
git branch -d gibboda-patch-4-1
git branch -d gibboda-patch-5

# Delete closed branches (use -D for force delete)
git branch -D copilot/improve-slow-code-efficiency
git branch -D gibboda-patch-1
git branch -D gibboda-patch-2
```

#### Delete Remote Branches

```bash
# Delete merged branches from remote
git push origin --delete copilot/configure-snyk-scan-settings
git push origin --delete copilot/fix-log-writing-issue
git push origin --delete copilot/fix-shellcheck-warning-log-file
git push origin --delete copilot/improve-inefficient-code
git push origin --delete copilot/improve-code-efficiency
git push origin --delete gibboda-patch-3
git push origin --delete gibboda-patch-4
git push origin --delete gibboda-patch-4-1
git push origin --delete gibboda-patch-5

# Delete closed branches from remote
git push origin --delete copilot/improve-slow-code-efficiency
git push origin --delete gibboda-patch-1
git push origin --delete gibboda-patch-2
```

### Method 3: GitHub Web Interface

You can also delete branches through the GitHub web interface:

1. Go to the repository on GitHub
2. Click on "branches" (next to the branch dropdown)
3. Find the branch you want to delete
4. Click the trash icon next to the branch name

## After Cleanup

After cleaning up branches, you can verify the remaining branches with:

```bash
# List all local branches
git branch

# List all remote branches
git branch -r

# Prune any stale remote-tracking branches
git remote prune origin
```

## Best Practices

1. **Always delete branches after merging** - Configure branch protection rules to automatically delete branches after PR merge
2. **Use descriptive branch names** - Makes it easier to identify the purpose of each branch
3. **Regular cleanup** - Perform branch cleanup periodically (e.g., monthly) to prevent accumulation
4. **Protect important branches** - Mark branches like `main`, `develop` as protected in GitHub settings

## Notes

- The cleanup script requires Git push permissions to delete remote branches
- If you don't have permissions, you'll need to ask a repository administrator to run the cleanup
- Always do a dry run first to verify which branches will be deleted
- The script will automatically skip the current branch and protected branches

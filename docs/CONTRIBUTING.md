# Contributing to gentoo-um890pro

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

## Commit Message Format

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for all commit messages. This standardized format enables automated version bumping and changelog generation.

### Format

Each commit message must follow this structure:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Type

The type must be one of the following:

- **feat**: A new feature (triggers MINOR or MAJOR version bump)
- **fix**: A bug fix (triggers PATCH version bump)
- **update**: An update or improvement (triggers PATCH version bump)
- **docs**: Documentation only changes (no version bump)
- **style**: Changes that don't affect code meaning (formatting, whitespace, etc.)
- **refactor**: Code change that neither fixes a bug nor adds a feature (triggers MAJOR version bump)
- **perf**: Performance improvement (triggers MAJOR version bump)
- **test**: Adding or updating tests
- **build**: Changes to build system or dependencies
- **ci**: Changes to CI configuration files and scripts
- **chore**: Other changes that don't modify src or test files
- **revert**: Revert a previous commit

### Scope (Optional)

The scope can be anything specifying the place of the commit change, for example:

- `kernel`
- `btrfs`
- `zfs`
- `installer`
- `rocm`
- `ci`

### Breaking Changes

Breaking changes must be indicated in one of two ways:

1. Add `!` after the type/scope: `feat!: breaking change description`
2. Add `BREAKING CHANGE:` footer in the commit body

Breaking changes trigger a MAJOR version bump.

### Examples

#### Feature (triggers minor bump)
```
feat(rocm): add ROCm 7.1 support for AMD Radeon 780M

Add ROCm installation and configuration for gfx1103 architecture.
Includes OpenCL runtime and compute stack.
```

#### Bug Fix (triggers patch bump)
```
fix(installer): resolve portage sets directory creation order

Move portage directory creation before first use to prevent
"No such file or directory" errors during kernel preservation.
```

#### Breaking Change (triggers major bump)
```
feat(kernel)!: change default kernel to gentoo-sources

BREAKING CHANGE: Default kernel changed from gentoo-kernel-bin
to gentoo-sources. Users must rebuild kernel after upgrade.
```

#### Documentation (no version bump)
```
docs(readme): update hardware requirements section

Clarify DDR5-5600 memory requirements and add Crucial part number.
```

#### Multiple Fixes (triggers minor bump when 2-6 fixes)
```
fix(plasma): correct qtbase wayland dependencies
fix(blender): add missing opensubdiv USE flags
fix(rocm): unmask rocm-comgr package
```

## Version Bumping

### Automatic Version Bumping

The project uses `scripts/bump-version.sh` to automatically determine version bumps based on commit messages:

```bash
# Analyze commits since last tag and bump version automatically
./scripts/bump-version.sh auto

# Allow running on dirty working tree (for testing)
./scripts/bump-version.sh auto --allow-dirty
```

### Version Bump Rules

- **MAJOR bump** (X.0.0):
  - Any single `feat`, `refactor`, or `perf` commit
  - Commits with breaking changes (`!` or `BREAKING CHANGE:`)
  - 7 or more `fix`/`update` commits

- **MINOR bump** (0.X.0):
  - 2-6 `fix`/`update` commits

- **PATCH bump** (0.0.X):
  - 0-1 `fix`/`update` commits

### Manual Version Bumping

For explicit control:

```bash
# Specific version with message
./scripts/bump-version.sh 1.2.3 "Release description"

# Quick bumps
./scripts/bump-version.sh patch
./scripts/bump-version.sh minor
./scripts/bump-version.sh major
```

## Pull Request Process

1. **Fork** the repository and create your branch from `main`
2. **Commit** your changes using Conventional Commits format
3. **Test** your changes thoroughly
4. **Run** `./scripts/bump-version.sh auto` if you're ready to bump the version
5. **Submit** a pull request

### PR Requirements

All pull requests must:

- Use Conventional Commits for all commit messages
- Pass all CI checks including:
  - Commit message validation
  - ShellCheck linting
  - Version consistency checks
- Include appropriate tests if adding new features
- Update documentation as needed

### CI Validation

The CI system validates:

- **Commit messages**: All commits must follow Conventional Commits format
- **PR titles**: Must follow Conventional Commits format; bot/automation PRs have stricter validation
- **Version consistency**: VERSION file, CHANGELOG.md, and installer script must match
- **Shell scripts**: All shell scripts must pass ShellCheck validation

PRs with non-compliant commit messages or PR titles will be blocked until fixed.

**Note for automation**: PR titles from Copilot, Codex, or other bots must be specific and descriptive. Generic terms like "Codex-generated", "Copilot updates", or vague descriptions like "fix issue" will be rejected by CI.

## Development Workflow

### Making Changes

1. Create a feature branch:
   ```bash
   git checkout -b feat/my-new-feature
   ```

2. Make your changes with proper commit messages:
   ```bash
   git commit -m "feat(installer): add new configuration option"
   ```

3. Push and create a PR:
   ```bash
   git push origin feat/my-new-feature
   ```

### Fixing Non-Compliant Commits

If CI rejects your commits, you'll need to rewrite them:

```bash
# Reword the last commit
git commit --amend

# Reword multiple commits interactively
git rebase -i HEAD~3

# Force push (only on feature branches!)
git push --force-with-lease
```

If CI validation fails, ensure that both your commit messages and PR title follow the Conventional Commits format. Fix non-compliant commits by rewording them as shown above. Update the PR title separately if it also fails validation.

## Testing

Before submitting:

1. Test the installer script in a VM or test environment
2. Run ShellCheck: `shellcheck $(git ls-files '*.sh')`
3. Verify version bumping works: `./scripts/bump-version.sh auto --allow-dirty`
4. Check generated CHANGELOG.md format

## Questions or Issues?

- Open an issue for bugs or feature requests
- Start a discussion for questions or ideas
- Ensure all issue titles and PR titles also use descriptive formats

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (GPL-3.0).

# Contributing to gentoo-um890pro

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

## Agent instruction files

Shared policy for every coding agent lives in [`AGENTS.md`](../AGENTS.md). That file is authoritative for agent roles (Cursor primary, Grok Build preferred secondary, other metered agents escalation-only), cost/duplicate-AI policy, deterministic validation, architecture, safety, testing, and change discipline.

Agent-specific overlays must not contradict `AGENTS.md`:

- Cursor: `.cursor/rules/`
- GitHub Copilot: `.github/instructions/copilot.instructions.md`
- Codex: `.github/instructions/codex.instructions.md`

This file remains authoritative for Conventional Commit types, scopes, breaking-change markers, version-bump thresholds, and the human contributor workflow.

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

The scope specifies the place of the change. It is optional, must match `[a-z0-9_-]+`, and may be any location that describes the commit. Prefer one of the scopes already used in issues and pull requests:

**Installer and hardware**

- `installer` — bootstrap script and install pipeline
- `kernel` — kernel install, cmdline, and dist-kernel
- `btrfs` — Btrfs root and snapshots
- `zfs` — ZFS pool and datasets
- `rocm` — ROCm / AMD GPU compute
- `plasma` — KDE Plasma desktop
- `blender` — Blender / HIP rendering

**Repository and tooling**

- `ci` — GitHub Actions and CI generally
- `commit-lint` — Conventional Commits validation workflow
- `workflows` — other GitHub workflow files
- `scripts` — helper scripts under `scripts/`
- `bump-version` — version bump script and its tests
- `tests` — test suite
- `docs` — documentation
- `changelog` — `docs/CHANGELOG.md`
- `readme` — `README.md`
- `security` — `SECURITY.md` and vulnerability policy
- `phase2` — Phase 2 installer rewrite
- `commits` — commit-history or git tooling

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

#### Security fix (triggers patch bump when it is the only fix)
```
fix(security): redact root password from installer logs

Avoid writing the entered root password to the install log.
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
# Analyze commits since last tag and rewrite version files
./scripts/bump-version.sh auto

# Allow running on dirty working tree (for testing)
./scripts/bump-version.sh auto --allow-dirty
```

`auto` determines the next version from Conventional Commits since the last tag, rewrites `VERSION`, `src/gentoo-um890pro-install.sh`, `docs/CHANGELOG.md`, and the supported-version table in `SECURITY.md` (when present), then exits **without committing or tagging**. After `auto`, commit and tag those files yourself. Do not run `patch` / `minor` / `major` or an explicit version on that dirty tree: tagging modes refuse uncommitted changes, and `--allow-dirty` would bump `VERSION` again or duplicate the changelog entry.

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
# Specific version with message (commits and creates annotated tag vX.Y.Z)
./scripts/bump-version.sh 1.2.3 "Release description"

# Quick bumps (also commit and create an annotated tag)
./scripts/bump-version.sh patch
./scripts/bump-version.sh minor
./scripts/bump-version.sh major
```

## Pull Request Process

1. **Fork** the repository and create your branch from `main`
2. **Commit** your changes using Conventional Commits format
3. **Test** your changes thoroughly
4. **Run** `./scripts/bump-version.sh auto` if you're ready to rewrite version files (this does not commit or tag)
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
- **Version consistency**: VERSION file, CHANGELOG.md, installer script, and SECURITY.md supported line must match
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

## Security

Do not open a public GitHub issue for security vulnerabilities. See [SECURITY.md](../SECURITY.md) for scope, private reporting channels, and disclosure process.

## Questions or Issues?

- Open an issue for bugs or feature requests
- Report vulnerabilities privately as described in [SECURITY.md](../SECURITY.md)
- Start a discussion for questions or ideas
- Ensure all issue titles and PR titles also use descriptive formats

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (GPL-3.0).

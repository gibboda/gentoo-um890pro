# AGENTS.md

Shared instructions for coding agents working in this repository, including Cursor,
GitHub Copilot, Claude, Codex, and other tools that consume `AGENTS.md`. This file
is repository guidance, not a Cursor-only contract. Follow the sections that apply
to the work you were asked to do.

## Multi-agent development policy

Optimize for an independent-developer budget. Do not assume unlimited tokens,
premium requests, AI credits, or paid-agent capacity.

### Primary agent

**Cursor Agent is the primary/default implementation agent** when the developer
has a choice of tools. Cursor should handle routine work itself:

- repository analysis
- planning
- implementation
- refactoring
- debugging
- testing
- CI failure remediation
- documentation
- commit preparation
- pull-request preparation

When another agent is already assigned the task (for example Copilot or Codex
on a GitHub issue), that agent should complete the work using this file and
should not bounce routine work to additional paid agents.

### GitHub is the source of truth

GitHub remains the control plane for:

- repositories
- Issues and Projects
- branches and pull requests
- GitHub Actions
- rulesets and branch protection
- CodeQL
- Dependabot
- secret scanning
- code scanning
- releases

Do not treat an agent's local checkout, chat history, or draft artifacts as
authoritative over GitHub state.

### Secondary / specialist agents

GitHub Copilot, Claude, Codex, and other paid or cloud agents are
**secondary/specialist** tools. Use them only when at least one of these is true:

- Cursor (or the already-assigned agent) cannot reliably complete the task
- an independent second opinion has substantial value
- security or architecture changes warrant additional review
- specialized reasoning is needed
- the developer explicitly requested that agent

Do **not** invoke multiple AI agents for the same routine task. Do not fan out
the same implementation, refactor, test run, or documentation edit to extra
agents "for coverage."

### Deterministic validation over AI review

Prefer the repository's existing checks over asking another model to review:

- `shellcheck` on tracked `*.sh` files (see **Lint / test / run** below)
- the Bash tests under `tests/`
- GitHub Actions (ShellCheck, commit-lint, version-check, version-consistency)
- `scripts/bump-version.sh` and other repository validation scripts
- CodeQL, Dependabot, secret scanning, and code scanning when those GitHub
  features are enabled

This repository has no compiled application, lockfile, formatter gate, or type
checker. Do not invent extra AI review passes to stand in for those.

AI reviews are **advisory**. They are not required merge gates. Exhaustion of
an optional AI agent's quota must not block development when required
deterministic validation passes. Required merge gates live in GitHub (Actions,
rulesets, branch protection), not in a model's availability.

### Agent-specific instruction files

Keep this file useful to every consumer. Cursor-product settings belong in
`.cursor/rules/` when they are IDE-only. Copilot and Codex PR-title rules live
in `.github/instructions/`. Do not duplicate those files here, and do not add
instructions that other agents cannot follow.

## Repository environment

This repository is a **Bash/POSIX shell project**: an automated Gentoo installer
for a Minisforum EliteMini UM890 Pro, plus supporting developer tooling (version
bumping, commit-lint helpers). There is no compiled application and no package
manager / lockfile — the "dev environment" is just Bash plus `shellcheck`.

### Services

There are no long-running services to start. Nothing needs to be launched in the
background; work is driven entirely by one-off shell commands. Cursor Cloud and
other ephemeral agent VMs follow the same rule: do not start extra daemons for
this repo.

### Lint / test / run

- **Lint** (matches the `ShellCheck` CI workflow): run `shellcheck` over every
  tracked shell script.
  ```bash
  shellcheck $(git ls-files '*.sh')
  ```
- **Tests** (plain Bash scripts under `tests/`, not wired into CI — run them
  directly):
  ```bash
  bash tests/test-conventional-commits.sh
  bash tests/test-install-profile-resolution.sh
  bash tests/test-bump-version.sh   # slower: creates temp git repos and runs many bump scenarios
  ```
- **Version tooling**: `scripts/bump-version.sh` derives the repo root from its
  own location, so it must stay under `scripts/`. Test it against a throwaway
  git repo (copy the script into a temp `scripts/` dir) rather than running it
  against this repo. Modes differ:
  - `auto` (and `auto --allow-dirty` on a dirty tree) rewrites `VERSION`,
    `docs/CHANGELOG.md`, the installer header, and the supported-version table
    in `SECURITY.md` (when that file exists), then **exits without committing
    or tagging**.
  - `patch`/`minor`/`major` and `./scripts/bump-version.sh <version> "message"`
    also commit those files and create an annotated `vX.Y.Z` tag.

### Running the installer (caution)

`src/gentoo-um890pro-install.sh` is **destructive**: it wipes disks, requires
`root`, a Gentoo live environment, and specific NVMe hardware. Do **not** run it
in a Cursor Cloud VM, CI runner, or any other non-target machine. To exercise
its logic safely, source it with the final `main "$@"` line stripped and call
individual functions (for example `resolve_profile`), which is exactly what
`tests/test-install-profile-resolution.sh` does:
```bash
source <(sed '/^[[:space:]]*main "\$@"/d' src/gentoo-um890pro-install.sh)
INSTALL_PROFILE=core resolve_profile
```

### Commit conventions

Commits and PR titles must follow [Conventional Commits](https://www.conventionalcommits.org/)
(`feat`, `fix`, `docs`, `refactor`, etc.) or the commit-lint CI will fail. See
`docs/CONTRIBUTING.md`. User-visible changes generally require a
`## [Unreleased]` bullet in `docs/CHANGELOG.md`.

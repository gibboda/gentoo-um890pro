# AGENTS.md

Shared instructions for coding agents working in this repository, including Cursor,
GitHub Copilot, Claude, Codex, and other tools that consume `AGENTS.md`. This file
is repository guidance, not a Cursor-only contract. Follow the sections that apply
to the work you were asked to do.

## Multi-agent development policy

### Roles

- Cursor Agent is the primary/default implementation agent.
- Grok Build is the preferred secondary agent when Cursor cannot complete the
  work and a second implementation path is still warranted.
- GitHub Copilot, Codex, Claude, and other metered cloud agents are
  specialist/escalation resources. They must not be invoked automatically for
  routine work.
- GitHub remains the source of truth and control plane for repositories,
  Issues and Projects, branches and pull requests, GitHub Actions, rulesets
  and branch protection, CodeQL, Dependabot, secret scanning, code scanning,
  and releases.
- Every agent follows the same repository policies when used.

### Default work for the primary agent

Keep routine work with Cursor whenever practical. Cursor handles:

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

Do not auto-escalate those tasks to Grok Build, GitHub Copilot, Codex,
Claude, or other metered cloud agents.

### Escalation and secondary use

Escalate only when at least one of the following is true:

- Cursor cannot reliably complete the task after a practical attempt
- an independent second opinion has substantial value
- security or architecture changes warrant additional review
- specialized reasoning is needed that Cursor cannot provide
- the developer explicitly requests a named secondary or specialist agent

Preferred order when escalation is justified:

1. Stay with Cursor and reuse existing findings, logs, PR discussion, and
   deterministic check output.
2. Use Grok Build as the preferred secondary implementation agent.
3. Use GitHub Copilot, Codex, Claude, or another metered cloud agent only as a
   specialist/escalation resource for a narrowly scoped need.

Do not invoke multiple paid or cloud agents for the same routine task. Before
starting a new paid-agent analysis, reuse prior agent findings, issue/PR
comments, CI results, and local validation output.
Minimize duplicate paid-agent analysis across the same change.

### Cost and capacity

Optimize AI usage for an independent-developer budget. Prefer Cursor for
default throughput. Do not assume unlimited tokens, premium requests, AI
credits, or paid-agent capacity. Metered specialist agents are scarce
resources, not parallel reviewers for every change.

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

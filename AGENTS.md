# AGENTS.md

Shared instructions for every coding agent that works in this repository,
including Cursor, Grok Build, GitHub Copilot, Claude, Codex, and other tools
that consume `AGENTS.md`. This file is repository guidance, not a Cursor-only
contract.

## Instruction authority

This file is authoritative for:

- shared agent roles and escalation policy
- cost and duplicate-AI policy
- deterministic validation policy
- repository-wide architecture and safety
- testing requirements
- change discipline

Agent-specific overlays must not contradict this file:

| Audience | Authoritative overlay |
| --- | --- |
| Cursor (IDE and Cloud) | `.cursor/rules/` |
| GitHub Copilot | `.github/instructions/copilot.instructions.md` |
| Codex | `.github/instructions/codex.instructions.md` |

Conventional Commit types, scopes, version-bump rules, and the human
contributor workflow are defined in `docs/CONTRIBUTING.md`. Do not copy
Cursor-only or GitHub-agent-only instructions into this file.

## Multi-agent development policy

### Roles

- Cursor Agent is the primary/default implementation agent.
- Grok Build is the preferred secondary implementation agent when available,
  if Cursor cannot complete the work and a second implementation path is still
  warranted.
- GitHub Copilot, Codex, Claude, and other metered cloud agents are
  specialist/escalation resources. They must not be invoked automatically for
  routine work. If Grok Build is unavailable, an available specialist agent
  may be used for a narrowly scoped escalation need.
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

1. Stay with Cursor and reuse existing findings, logs, issue/PR discussion, and
   deterministic check output.
2. Use Grok Build as the preferred secondary implementation agent when
   available.
3. If Grok Build is unavailable, use an available specialist agent such as
   GitHub Copilot, Codex, Claude, or another explicitly approved agent for the
   narrowly scoped escalation need.

Do not invoke multiple paid or cloud agents for the same routine task. Before
starting a new paid-agent analysis, reuse prior agent findings, logs, issue/PR
discussion, CI results, tests, and local validation output.
Minimize duplicate paid-agent analysis across the same change.

### Cost and capacity

Optimize AI usage for an independent-developer budget. Prefer Cursor for
default throughput. Do not assume unlimited tokens, premium requests, AI
credits, or paid-agent capacity. Metered specialist agents are scarce
resources, not parallel reviewers for every change.

## Deterministic validation over AI review

Prefer the repository's existing checks over asking another model to review:

- `shellcheck` on tracked `*.sh` files (see **Testing** below)
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

## Repository architecture and safety

This repository is a **Bash/POSIX shell project**: an automated Gentoo installer
for a Minisforum EliteMini UM890 Pro, plus supporting developer tooling (version
bumping, commit-lint helpers). There is no compiled application and no package
manager / lockfile — the "dev environment" is just Bash plus `shellcheck`.

### Services

There are no long-running services to start. Nothing needs to be launched in the
background; work is driven entirely by one-off shell commands. Do not start
extra daemons for this repo.

### Running the installer (caution)

`src/gentoo-um890pro-install.sh` is **destructive**: it wipes disks, requires
`root`, a Gentoo live environment, and specific NVMe hardware. Do **not** run it
in CI, an ephemeral agent VM, or any other non-target machine. To exercise
its logic safely, source it with the final `main "$@"` line stripped and call
individual functions (for example `resolve_profile`), which is exactly what
`tests/test-install-profile-resolution.sh` does:
```bash
source <(sed '/^[[:space:]]*main "\$@"/d' src/gentoo-um890pro-install.sh)
INSTALL_PROFILE=core resolve_profile
```

## Testing

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
  bash tests/test-on-err-trap.sh
  bash tests/test-bump-version.sh   # slower: creates temp git repos and runs many bump scenarios
  ```
- **Version tooling**: `scripts/bump-version.sh` derives the repo root from its
  own location, so it must stay under `scripts/`. Test the script itself
  against a throwaway git repo (copy it into a temp `scripts/` dir) rather
  than running those script tests against this repo. Modes differ:
  - `auto` (and `auto --allow-dirty` on a dirty tree) rewrites `VERSION`,
    `docs/CHANGELOG.md`, the installer header, and the supported-version table
    in `SECURITY.md` (when that file exists), then **exits without committing
    or tagging**.
  - `patch`/`minor`/`major` and `./scripts/bump-version.sh <version> "message"`
    also commit those files and create an annotated `vX.Y.Z` tag.

## Change discipline

Commits and PR titles must follow [Conventional Commits](https://www.conventionalcommits.org/)
(`feat`, `fix`, `docs`, `refactor`, etc.) or the commit-lint CI will fail.
`docs/CONTRIBUTING.md` is authoritative for types, scopes, breaking-change
markers, and version-bump thresholds. User-visible changes generally require a
`## [Unreleased]` bullet in `docs/CHANGELOG.md`.

Do not weaken testing, safety, Conventional Commit, PR-title, hardware,
architecture, or validation requirements. Bot/automation PR titles have extra
CI constraints; Copilot and Codex overlays spell those out without changing
the shared format.

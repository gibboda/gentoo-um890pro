# AGENTS.md

## Cursor Cloud specific instructions

This repository is a **Bash/POSIX shell project**: an automated Gentoo installer for a
Minisforum EliteMini UM890 Pro, plus supporting developer tooling (version bumping,
commit-lint helpers). There is no compiled application and no package manager / lockfile —
the "dev environment" is just Bash plus `shellcheck`.

### Services

There are no long-running services to start. Nothing needs to be launched in the background;
work is driven entirely by one-off shell commands.

### Lint / test / run

- **Lint** (matches the `ShellCheck` CI workflow): run `shellcheck` over every tracked
  shell script.
  ```bash
  shellcheck $(git ls-files '*.sh')
  ```
- **Tests** (plain Bash scripts under `tests/`, not wired into CI — run them directly):
  ```bash
  bash tests/test-conventional-commits.sh
  bash tests/test-install-profile-resolution.sh
  bash tests/test-bump-version.sh   # slower: creates temp git repos and runs many bump scenarios
  ```
- **Version tooling**: `scripts/bump-version.sh` derives the repo root from its own location,
  so it must stay under `scripts/`. Test it against a throwaway git repo (copy the script into
  a temp `scripts/` dir) rather than running `auto` against this repo, since it writes
  `VERSION`, `docs/CHANGELOG.md`, and the installer header and creates annotated `vX.Y.Z` tags.
  Use `./scripts/bump-version.sh auto --allow-dirty` for a dirty tree.

### Running the installer (caution)

`src/gentoo-um890pro-install.sh` is **destructive**: it wipes disks, requires `root`, a Gentoo
live environment, and specific NVMe hardware. Do **not** run it in the VM. To exercise its
logic safely, source it with the final `main "$@"` line stripped and call individual functions
(for example `resolve_profile`), which is exactly what `tests/test-install-profile-resolution.sh`
does:
```bash
source <(sed '/^[[:space:]]*main "\$@"/d' src/gentoo-um890pro-install.sh)
INSTALL_PROFILE=core resolve_profile
```

### Commit conventions

Commits and PR titles must follow [Conventional Commits](https://www.conventionalcommits.org/)
(`feat`, `fix`, `docs`, `refactor`, etc.) or the commit-lint CI will fail. See
`docs/CONTRIBUTING.md`. User-visible changes generally require a `## [Unreleased]` bullet in
`docs/CHANGELOG.md`.

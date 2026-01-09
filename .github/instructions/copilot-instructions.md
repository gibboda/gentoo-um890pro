# Repository rules (must follow)

## Versioning & Changelog (MANDATORY)
- If you change any code, you MUST run: ./bump-version.sh
- ./bump-version.sh is the single source of truth for:
  - version numbers across the repo
  - CHANGELOG updates
- If changes do not require a version bump, explicitly state why in the PR description.

## PR acceptance criteria
- CI must pass.
- PR must include:
  - updated versions (as produced by bump-version.sh)
  - updated CHANGELOG entry

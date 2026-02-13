# Codebase Issue Tasks (Proposed)

## 1) Typo fix task
**Task:** Fix the singular/plural typo in `IMPLEMENTATION_COMPLETE.md`: “pre-enforcement commit” → “pre-enforcement commits”.

**Why:** The bullet describes handling for multiple legacy commits, so the singular noun is a typo/wording error.

**Acceptance criteria:**
- Update the phrase to “pre-enforcement commits”.
- Do a quick pass for similar singular/plural wording issues in historical summary docs.

## 2) Bug fix task
**Task:** Fix `on_err()` in `gentoo-um890pro-install.sh` so fatal errors are not silently suppressed.

**Why:** `on_err()` disables `errexit` (`set +e`) before checking whether `-e` is active. That check then always fails and returns early, which can skip intended fatal error handling.

**Acceptance criteria:**
- Preserve and evaluate prior shell option state correctly (or remove the broken check).
- Ensure failing commands emit the error context and exit non-zero.
- Add/adjust a small regression test (or reproducible script snippet) validating behavior.

## 3) Comment/documentation discrepancy task
**Task:** Align `docs/CONVENTIONAL_COMMITS.md` test-count documentation with actual `tools/test-conventional-commits.sh` coverage.

**Why:** The docs claim fixed category totals (42 with a specific valid/invalid/edge/skipped split), but the script now includes an additional “Codex/Copilot PR title examples” section, so the documented breakdown is stale.

**Acceptance criteria:**
- Update the docs with current counts, or change wording to avoid brittle hardcoded numbers.
- Add a note that counts may evolve as new cases are added.

## 4) Test improvement task
**Task:** Improve `tools/test-bump-version.sh` to verify annotated tag creation in auto mode.

**Why:** Project docs state version bumps must create an annotated Git tag, but current tests verify version/changelog updates only and do not assert tag creation/annotation.

**Acceptance criteria:**
- After each test run, assert expected tag (e.g., `vX.Y.Z`) exists.
- Assert the tag is annotated (not lightweight), e.g., via `git cat-file -t`.
- Fail test with actionable output if tagging is missing/incorrect.

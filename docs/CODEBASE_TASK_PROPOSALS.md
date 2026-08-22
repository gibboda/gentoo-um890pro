# Codebase Issue Tasks (Proposed)

These four tasks were identified against the current tree and are distinct from
the already-open issues #176–#179.

## 1) Typo fix task

**Task:** Rename the misspelled Blender USE flag `oslray` to `osl` in
`src/gentoo-um890pro-install.sh`.

**Why:** The installer writes `oslray` into `/etc/portage/package.use/blender`
and in the adjacent comment. Gentoo `media-gfx/blender` has an `osl` USE flag
(Open Shading Language for Cycles). There is no `oslray` flag, so the token is a
misspelling and Portage will ignore or reject it.

**Acceptance criteria:**
- Replace `oslray` with `osl` in both the `package.use` atom and the GPU
  Rendering comment.
- Do not change unrelated Blender USE flags in the same pass unless they are
  part of a follow-up bug fix.

## 2) Bug fix task

**Task:** Point the OpenVDB `package.use` atom at `media-gfx/openvdb` instead of
the obsolete `sci-libs/openvdb` category.

**Why:** The installer writes:

```
sci-libs/openvdb abi8-compat blosc numpy openvdb-compression python zlib
```

OpenVDB in Gentoo is `media-gfx/openvdb`. A `package.use` line for a package
that is not in the tree never applies, so Blender's `openvdb` dependency can
emerge with the wrong USE flags (or fail `REQUIRED_USE`).

**Acceptance criteria:**
- Change the atom to `media-gfx/openvdb`.
- Recheck the listed USE flags against current `media-gfx/openvdb` IUSE and
  drop or replace flags that no longer exist.
- Confirm the Blender `openvdb` USE flag still matches the dependency the
  ebuild pulls in.

## 3) Comment/documentation discrepancy task

**Task:** Fix the installer download path and profile instructions in
`docs/INSTALLATION_GUIDE.md` so they match the current repository layout and
`INSTALL_PROFILE` behavior.

**Why:** The guide tells users to download a root-level script that no longer
exists:

```
wget https://raw.githubusercontent.com/gibboda/gentoo-um890pro/main/gentoo-um890pro-install.sh
```

The installer lives at `src/gentoo-um890pro-install.sh` (`README.md` already
uses that path). The same section also tells users to set `INSTALL_KDE_PLASMA`,
`INSTALL_BLENDER`, `INSTALL_COMFYUI`, `INSTALL_ROCM`, and `INSTALL_DUAL_KERNEL`
directly, but `resolve_profile()` overwrites those toggles from `INSTALL_PROFILE`
(default `core-openrc-dualkernel`). Following the guide as written 404s on
download, and even after a local copy is obtained, editing those feature
toggles has no effect.

**Acceptance criteria:**
- wget / nano / run commands use `src/gentoo-um890pro-install.sh`.
- Document `INSTALL_PROFILE` (`core` / `desktop` / `full-ai` and canonical
  names) as the way to select desktop and AI features.
- Stop presenting the overwritten per-feature toggles as independently
  editable settings, or clearly state that `resolve_profile` overrides them.

## 4) Test improvement task

**Task:** Stop duplicating Conventional Commits validation in
`tests/test-conventional-commits.sh`; exercise the real
`validate_conventional_commit()` from `scripts/bump-version.sh`.

**Why:** The test copies the validator inline. CI
(`.github/workflows/commit-lint.yml`) also skips subjects such as
`Apply suggestions from code review`, which the copied function and test cases
do not cover. If the real validator or skip list changes, this suite can keep
passing while production validation drifts.

**Acceptance criteria:**
- Tests call the production `validate_conventional_commit()` (extract/source it
  without executing bump-version side effects such as dirty-tree checks).
- Add cases for skip patterns that CI already treats as valid, including
  `Apply suggestions from code review`.
- Fail with an actionable message if a case does not match the expected
  VALID/INVALID result.

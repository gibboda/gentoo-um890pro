# Installer Audit & Rewrite Blueprint (Review-Only)

## Scope

This document is a strict, review-only audit of the current installer and an architecture blueprint for a rewrite that cleanly supports three installation options while preserving the current OS-disk + data-disk model.

No implementation changes are proposed in this document; this is a planning artifact.

## Requested Target Options

1. **Option 1**: OpenRC + dual-kernel (binary fallback + tuned source kernel) + bootloader
2. **Option 2**: Option 1 + KDE Plasma 6 with Wayland
3. **Option 3**: Option 2 + AI Stock + DigestAI + GAIA

---

## Current Installation Process (Mapped from `gentoo-um890pro-install.sh`)

### Top-level flow

The installer currently executes a linear, monolithic pipeline in `main()`:

1. preflight (`require_root`, `require_uefi`, command checks)
2. destructive disk ops (`confirm_disks`, `stop_mounts`, `partition_disks`, `format_os`)
3. mount and stage3 prep (`mount_btrfs_layout`, `fetch_stage3_and_prep`)
4. base/chroot config (`install_base_system`)
5. kernel install (`install_kernel`)
6. boot config (`configure_fstab_bootloader`)
7. services + optional feature blocks
8. prompts and final reboot path

This is functionally complete but tightly coupled and mostly controlled by top-level booleans.

### Existing toggles relevant to requested options

The script already has most conceptual building blocks, but not as formal install profiles:

- `INIT_SYSTEM` (`openrc` or `systemd`)
- `INSTALL_DUAL_KERNEL` (`yes/no`)
- `USE_BINARY_KERNEL` (`yes/no`)
- `INSTALL_KDE_PLASMA` (`yes/no`)
- `INSTALL_ROCM`, `INSTALL_COMFYUI`, `INSTALL_BLENDER` (`yes/no`)

### Existing component boundaries (coarse modules)

The current function-level structure maps to these domains:

- **Platform**: preflight checks, logging, chroot wrappers
- **Storage**: partitioning, Btrfs layout, ZFS pool setup
- **Base OS**: profile selection, locale/timezone, Portage config
- **Kernel**: single binary / single source / dual-kernel branches
- **Boot**: fstab + rEFInd setup
- **Desktop**: KDE Plasma + display manager path
- **AI stack (partial)**: ROCm + ComfyUI helper + Blender

---

## Strict Audit Findings

## What is strong today

- Good hard-fail guardrails for root/UEFI/disk sanity
- Practical dual-disk split (Btrfs OS + ZFS data)
- Kernel strategy already supports fallback safety with dual-kernel mode
- Bootloader integration is explicit and deterministic
- OpenRC and systemd paths already separated where needed

## What blocks clean profile-based installation

1. **Configuration is boolean-heavy, not profile-driven**  
   The script allows many combinations, including invalid/untested mixes. The requested three options should be explicit profiles rather than free-form booleans.

2. **Monolithic orchestration in `main()`**  
   `main()` is a fixed pipeline with optional calls. This makes dependency reasoning hard (e.g., AI depends on GPU/runtime/network/userland expectations).

3. **Feature dependency graph is implicit**  
   There is no formal resolver stating relationships like:
   - KDE requires desktop/session stack
   - AI suite requires GPU runtime + Python toolchain + datasets/layout

4. **No transaction-like phase boundaries**  
   Destructive steps and high-level feature steps are not checkpointed as explicit phases with resume semantics.

5. **AI scope mismatch with new requested products**  
   Current script includes ROCm/ComfyUI/Blender, but no first-class “AI Stock”, “DigestAI”, or “GAIA” components/contracts.

---

## Best Rewrite Strategy (Recommended)

Use a **profile-first modular installer** with a dependency-resolved execution graph.

## Proposed architecture

## 1) Explicit profile contract

Define exactly three supported profiles:

- `core-openrc-dualkernel`
- `desktop-openrc-dualkernel-kde`
- `full-openrc-dualkernel-kde-ai`

These are immutable, tested targets. Advanced per-feature overrides should be disallowed initially (or gated behind `--expert`).

## 2) Declarative module registry

Model each install concern as a module with metadata:

- `id`
- `description`
- `depends_on[]`
- `conflicts_with[]`
- `phase` (preflight, disk, base, kernel, boot, desktop, ai, finalize)
- `apply()`
- `verify()`

This converts implicit dependencies into explicit graph logic.

## 3) Phase engine

Run modules by ordered phases with checkpoint files:

- `00_preflight`
- `10_disk_layout`
- `20_base_system`
- `30_kernel`
- `40_bootloader`
- `50_desktop`
- `60_ai`
- `90_finalize`

Persist phase completion under `/var/lib/um890-installer/state/` so failures can resume from last clean checkpoint.

## 4) Unified storage model (fixed for all 3 options)

Keep storage invariant across profiles:

- OS disk: GPT + ESP + Btrfs root subvolumes
- Data disk: GPT + ZFS pool/datasets

Only higher layers (desktop/AI) vary by profile.

## 5) Productized AI extension layer

Treat AI Option 3 as a bundle with explicit contracts:

- `ai-stock` module
- `digestai` module
- `gaia` module

Each must declare:

- package/source origin and pinning policy
- system users/groups
- service model (OpenRC scripts)
- data paths on ZFS (e.g., `/data/ai/*`)
- health checks and post-install smoke tests

---

## Option Mapping for Rewrite

## Option 1 → Core profile

**Includes:**

- OpenRC base
- dual-kernel strategy
  - kernel A: binary fallback
  - kernel B: tuned source kernel
- rEFInd bootloader

**Excludes:** desktop + AI

## Option 2 → Desktop profile

**Includes:** Option 1 +

- KDE Plasma 6
- Wayland session stack
- SDDM + required OpenRC session plumbing (`elogind`, `dbus`, etc.)

## Option 3 → Full AI profile

**Includes:** Option 2 +

- AI Stock
- DigestAI
- GAIA
- shared AI runtime prerequisites and dataset/model directory contracts on ZFS data disk

---

## Suggested File/Module Layout for Rewrite

```text
installer/
  bin/
    um890-installer            # CLI entrypoint
  core/
    runner.sh                  # phase executor + checkpoints
    profiles.sh                # 3 explicit profiles
    resolver.sh                # dependency/conflict resolution
    state.sh                   # checkpoint persistence
  modules/
    preflight.sh
    disks_btrfs_zfs.sh
    base_openrc.sh
    kernel_dual.sh
    boot_refind.sh
    desktop_kde_wayland.sh
    ai_stock.sh
    ai_digestai.sh
    ai_gaia.sh
    finalize.sh
  lib/
    chroot.sh
    log.sh
    verify.sh
```

---

## Risk Controls to Preserve During Rewrite

- Keep explicit destructive confirmation gate (`WIPE-AND-INSTALL` equivalent)
- Keep strict disk identity requirement (prefer `/dev/disk/by-id/*`)
- Keep dual-kernel fallback bootability as non-optional for all 3 profiles
- Keep post-phase verification to fail fast before next phase
- Keep clear rollback/recovery instructions per phase

---

## Migration Plan (Low-Risk)

1. **Phase 0: Extract and wrap existing functions** into module files without behavior change.
2. **Phase 1: Introduce profile selector** with only three supported outputs.
3. **Phase 2: Add dependency resolver + checkpoints**.
4. **Phase 3: Add AI Stock/DigestAI/GAIA modules** with pinned sources and service checks.
5. **Phase 4: Remove legacy free-form toggle matrix** (or hide behind expert mode).

---

## Acceptance Criteria for Rewrite

- Installer CLI presents exactly 3 primary choices matching requested options.
- Each choice resolves to deterministic module set + order.
- Option 1 installs and boots with both kernels visible/selectable.
- Option 2 lands in functional KDE Plasma Wayland session.
- Option 3 provisions AI Stock + DigestAI + GAIA with validated service/data paths.
- Failed installs can resume from last completed phase without re-wiping disks unless requested.

---

## Recommended Next Step

Implement the rewrite behind a new entrypoint (`installer/bin/um890-installer`) while keeping `gentoo-um890pro-install.sh` as a compatibility wrapper during transition. This enables staged validation and rollback to known-good behavior.

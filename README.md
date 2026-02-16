# Gentoo installer for Minisforum EliteMini UM890 Pro

This repository contains an automated Gentoo bootstrap installer targeted at a Minisforum EliteMini UM890 Pro (UEFI, 2× NVMe). The installer provisions the OS onto one NVMe (Btrfs root + EFI) and a ZFS pool for data/AI models on the other NVMe.

Important: running the installer will irreversibly wipe the selected disks.

Script: [gentoo-um890pro-install.sh](gentoo-um890pro-install.sh)

## Target Hardware Specifications

This installer is specifically optimized for:

- **System**: Minisforum EliteMini UM890 Pro
- **CPU**: AMD Ryzen 9 8945HS (Zen 4, 8C/16T)
- **iGPU**: AMD Radeon 780M (RDNA 3, gfx1103)
- **RAM**: 2× Crucial 48GB DDR5-5600 (CT48G56C46S5) = 96GB total
- **Storage**: 2× Crucial P3 Plus 4TB NVMe SSD (CT4000P3PSSD8)

See [docs/HARDWARE_SETUP.md](docs/HARDWARE_SETUP.md) for detailed hardware information.

## Documentation

- **[Installation Guide](docs/INSTALLATION_GUIDE.md)** - Step-by-step installation instructions
- **[Installer Rewrite Audit](docs/INSTALLER_REWRITE_AUDIT.md)** - Review-only audit, process map, and modular rewrite blueprint for 3 install options
- **[Kernel Management](docs/KERNEL_MANAGEMENT.md)** - Kernel backup, optimization, and fallback strategies
- **[Hardware Setup](docs/HARDWARE_SETUP.md)** - BIOS configuration, hardware verification
- **[System Specifications](docs/SYSTEM_SPECS.md)** - Complete hardware specifications
- **[Optimization Guide](docs/OPTIMIZATION_GUIDE.md)** - Performance tuning and optimizations
- **[Conventional Commits](docs/CONVENTIONAL_COMMITS.md)** - Commit linting and version bump rules

## Contributing

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for all commit messages. This enables automated version bumping and changelog generation.

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines on:
- Commit message format and types
- Version bumping workflow
- Pull request requirements
- CI validation process

**Quick reference:**
- `feat(scope): description` - New feature
- `fix(scope): description` - Bug fix
- `docs: description` - Documentation changes
- `refactor(scope): description` - Code refactoring
- `revert: description` - Revert a previous commit

All commits must follow this format or CI checks will fail.

## Overview

- OS disk: EFI System Partition (FAT32) + Btrfs root with subvolumes (`@`, `@home`, `@var`, `@snapshots`).
- Data disk: single-partition ZFS pool with datasets under `ZFS_MNT_BASE` (default `/data`).
- Init system: `openrc` (default) or `systemd` (controlled by `INIT_SYSTEM`).
- Kernel: installs `gentoo-kernel-bin` by default for fast setup. Use `switch-to-source-kernel` after installation to optimize.
- Kernel (optional): set `INSTALL_DUAL_KERNEL=yes` to install both a binary fallback and a tuned source kernel with separate boot entries.
- Bootloader: rEFInd (UEFI).
- Desktop: KDE Plasma 6 with Wayland (controlled by `INSTALL_KDE_PLASMA`).
- Snapshots: optional automated Btrfs **root** snapshots (OS disk) with `manage-snapshots` (timer for systemd or cron for OpenRC) when `ENABLE_SNAPSHOTS=yes`—ZFS data disk remains unchanged.
- Boot safety: ML-based boot target recommendations via `ml-boot-selector`, logged by `update-refind-default` and compatible with rEFInd entries.
- AI stack: ROCm for Radeon 780M, ComfyUI setup script with SDXL/UMA optimizations, and Blender configured for HIP rendering.
- Interactive: requires typed confirmation (`WIPE-AND-INSTALL`), prompts for root password, optional user creation.

### OpenRC zram swap (AI-friendly)

If `INIT_SYSTEM="openrc"`, the installer sets up a simple OpenRC-managed zram swap device.

- Service: `/etc/init.d/zram` (enabled in the `boot` runlevel)
- Config: `/etc/conf.d/zram`
- Defaults: zram size = RAM/4, compression = `zstd` (if supported), swap priority = `100`

This is intended to keep the system “feeling like Gentoo” while still providing a fast compressed swap buffer that helps with bursty AI workloads.

## Requirements (live environment)

- Booted in UEFI mode.
- Working network.
- Run as `root`.
- The following commands must be available (the script checks/uses these):
  - `sgdisk` (gptfdisk)
  - `mkfs.vfat` (dosfstools), `mkfs.btrfs` (btrfs-progs)
  - `tar`, `wget`
  - `lsblk`, `blkid`, `awk`, `sed`

## Usage

1. Boot a Gentoo live environment in UEFI mode and become `root`.
2. Put [gentoo-um890pro-install.sh](gentoo-um890pro-install.sh) on the live system.
3. Edit variables at the top of the script to match your disks and preferences.
4. Run:

```bash
chmod +x gentoo-um890pro-install.sh
./gentoo-um890pro-install.sh
```

## Important configuration variables (top of script)

- `HOSTNAME` — hostname to set in the installed system.
- `OS_DISK` — device for OS (defaults to `/dev/nvme0n1`). Prefer `/dev/disk/by-id/...` paths.
  - Example for Crucial P3 Plus: `/dev/disk/by-id/nvme-CT4000P3PSSD8_SERIAL1`
- `DATA_DISK` — device used for ZFS pool (defaults to `/dev/nvme1n1`). Prefer `/dev/disk/by-id/...` paths.
  - Example for Crucial P3 Plus: `/dev/disk/by-id/nvme-CT4000P3PSSD8_SERIAL2`
- `ESP_SIZE_MIB` — size of the EFI partition.
- `BTRFS_LABEL`, `ESP_LABEL` — filesystem labels.
- `MNT`, `ESP_MNT`, `ZFS_MNT_BASE` — mountpoints used during install.
- `INIT_SYSTEM` — `openrc` (default) or `systemd`.
- `USE_BINARY_KERNEL` — `yes` to install `gentoo-kernel-bin`.
- `INSTALL_KDE_PLASMA` — `yes` to install KDE Plasma 6 + Wayland + SDDM.
- `INSTALL_BLENDER` — `yes` to install Blender 3D creation suite with OpenGL and Vulkan support.
- `INSTALL_COMFYUI` — `yes` to set up ComfyUI for AI image generation with SDXL support (manual setup required post-install).
- `INSTALL_ROCM` — `yes` to install ROCm for AMD GPU compute acceleration.
- `INSTALL_DUAL_KERNEL` — `yes` to install two independent kernels: a binary `gentoo-kernel-bin` fallback plus a custom-built `gentoo-sources` kernel with a unique `-um890-tuned` LOCALVERSION and per-kernel initramfs/boot artifacts.
- `ENABLE_SNAPSHOTS` — `yes` to set up automated Btrfs snapshot management.
- `ZPOOL` — name of the ZFS pool created (default `tank`).
- `COMMON_FLAGS` — compile flags written to `make.conf`.
- `TIMEZONE`, `LOCALE` — timezone/locale written into the installed system.

### Storage: Crucial P3 Plus 4TB NVMe (CT4000P3PSSD8)

This installer is optimized for the **Crucial P3 Plus 4TB** (model CT4000P3PSSD8):
- **Capacity**: 4TB per drive (3.7 TiB usable, 7.4 TiB total)
- **Interface**: PCIe 4.0 x4, NVMe 1.4
- **Performance**: Up to 4,800 MB/s read, 4,100 MB/s write
- **Architecture**: DRAM-less design with HMB (Host Memory Buffer)
- **Endurance**: 800 TBW per drive

**Drive identification**:
```bash
# List drives with model numbers
lsblk -o NAME,SIZE,MODEL

# Find stable device paths
ls -l /dev/disk/by-id/ | grep CT4000P3PSSD8
```

**NVMe queue tuning (HMB-aware)**: The installer configures udev rules for generic NVMe queue tuning on these DRAM-less, HMB-capable drives. It does **not** change HMB size (for example, it does not write to `device/hmb_size`; HMB sizing requires vendor-specific or `nvme-cli` admin commands). The optional/manual HMB sizing steps and more aggressive tuning examples are documented in [OPTIMIZATION_GUIDE.md](docs/OPTIMIZATION_GUIDE.md) and are **not** applied automatically by the installer.

### Tuning zram (OpenRC)

If you use OpenRC, tune zram by editing `/etc/conf.d/zram` in the installed system:

- `ZRAM_SIZE` — set an explicit size like `"24G"` (leave empty for RAM/4)
- `ZRAM_COMP_ALGO` — e.g. `zstd`, `lz4`, `lzo` (only applied if the kernel supports it)
- `ZRAM_SWAP_PRIORITY` — higher prefers zram over disk swap

Manage it like any other OpenRC service:

```bash
rc-service zram start
rc-service zram stop
rc-update add zram boot
```

## After installation

The script prints the final steps. In general:

```bash
umount -R /mnt/gentoo
reboot
```

After reboot, ZFS datasets are mounted under `ZFS_MNT_BASE` (default `/data`).

### Post-install helpers

The installer places helper commands in `/usr/local/bin`:

- `setup-comfyui` — clones and configures ComfyUI with ROCm/UMA settings, installs dependencies, and creates `launch-comfyui-uma.sh`.
- `manage-snapshots {create|list|rollback|cleanup}` — manual snapshot utility; a daily timer/cron is enabled when `ENABLE_SNAPSHOTS=yes`.
- `ml-boot-selector` — ML heuristics that recommend the safest boot target; `update-refind-default` logs the recommendation for rEFInd.
- `update-refind-default` — requires `jq` (Gentoo package `app-misc/jq`) to parse the ML selector JSON output; the installer does not install this automatically, so you may need to `emerge app-misc/jq` for this helper to work.
- `switch-to-source-kernel` — guided switch from `gentoo-kernel-bin` to `gentoo-kernel` while preserving existing kernels.
- `manage-kernels {list|preserve|clean|info}` — inspect, preserve, or clean kernel versions.

### Kernel optimization and backup

The installer uses a binary kernel (`gentoo-kernel-bin`) by default for fast initial setup. To switch to a source kernel for optimization and customization:

```bash
sudo switch-to-source-kernel
```

This helper script will:
- **Preserve old kernel versions automatically** for backup/fallback
- Install the source kernel (`sys-kernel/gentoo-kernel`)
- Automatically replace the binary kernel in the same slot
- Keep your kernel configuration
- Optionally customize kernel config with `menuconfig`
- Guide you through the process (takes 30-60 minutes to build)

#### Kernel backup and fallback strategy

- **Old kernels are kept automatically**: The system is configured to preserve previous kernel versions as backups
- **Boot menu access**: All installed kernel versions appear in the rEFInd boot menu
- **Safe upgrades**: When upgrading kernels, old versions remain bootable until you manually remove them
- **Multiple versions supported**: Keep 2-3 kernel versions for safety
- **Slot-based system**: Each kernel version uses a different slot (e.g., 6.12.58, 6.13.0)

**Important**: Binary and source kernels cannot coexist in the same version/slot. If you have kernel 6.12.58 as binary, installing source 6.12.58 will replace it. However, you can keep binary 6.12.58 AND source 6.13.0 (different versions).

View preserved kernels:
```bash
cat /etc/portage/sets/kernels
eselect kernel list
```

### Note: ZFS and binary kernels

The installer uses `sys-fs/zfs-kmod`, which builds kernel modules. If `USE_BINARY_KERNEL=yes` and the module build fails due to missing kernel build trees/config, the script will automatically install `sys-kernel/gentoo-kernel` and retry the ZFS install.

## Versioning

- Current version: [VERSION](VERSION)
- Changelog: [CHANGELOG.md](CHANGELOG.md)
- Bumping versions: [scripts/bump-version.sh](scripts/bump-version.sh)

The bump-version.sh script supports multiple modes:

**Auto mode** (Conventional Commits-based):
```bash
./scripts/bump-version.sh auto
```
- Automatically determines version bump based on commit messages since last tag
- Follows Conventional Commits specification
- Version bump rules:
  - **Major** (X+1.0.0): `feat`, `refactor`, `perf`, breaking changes (! or BREAKING CHANGE), or ≥7 fixes
  - **Minor** (X.Y+1.0): 2-6 `fix` or `update` commits
  - **Patch** (X.Y.Z+1): 0-1 `fix` or `update` commits
- Groups CHANGELOG.md entries by type (Fixes, Changes, Performance, Refactors, Other)

**Shortcut modes**:
```bash
./scripts/bump-version.sh patch   # Increment patch version
./scripts/bump-version.sh minor   # Increment minor version
./scripts/bump-version.sh major   # Increment major version
```

**Manual mode** (explicit version):
```bash
./scripts/bump-version.sh 0.1.2 "Short summary of changes"
```

All modes update VERSION, gentoo-um890pro-install.sh, and CHANGELOG.md consistently.
All version bumps must create an annotated Git tag (`vX.Y.Z`). `bump-version.sh` enforces tag creation and will fail if the tag already exists or cannot be created.

Note: `VERSION` is enforced as `X.Y.Z` semver by CI.

## GitHub Actions: permissions & releases

- Required permissions: the release workflow uses `contents: write` to create tags/releases.
- Label format: add a PR label matching `release: vX.Y.Z` or `release vX.Y.Z`.
- Manual release: run the workflow via `workflow_dispatch` (optional inputs).

Note on forks: workflows triggered from forked PRs typically run with a read-only token, so tagging/releases will fail with errors like “Resource not accessible by integration”. In that case, run the release as a maintainer (for example via `workflow_dispatch` or after merging).

Optional `REPO_PAT`: if you add a PAT secret named `REPO_PAT`, the release workflow prefers it for authenticated pushes/tags.

## CI badge

![version-check](https://github.com/gibboda/gentoo-um890pro/actions/workflows/version-check.yml/badge.svg)

## Snyk security scanning

This repository uses Snyk for security scanning. The `.snyk` file configures which files and directories should be excluded from scanning:

- Version control directories (`.git/`, `.github/`)
- IDE directories (`.vscode/`)
- Backup files (`*.bak`, `*.backup`, `*.old`, `*.orig`)
- Temporary files (`*.tmp`, `*.temp`, `*.swp`, `*.swo`, `*~`)
- Build artifacts and common directories (`dist/`, `build/`, `node_modules/`, etc.)
- Log files (`*.log`)

To customize exclusions, edit the `.snyk` file in the repository root.

## Branch cleanup

This repository includes a script to help clean up merged and stale Git branches. After PRs are merged or closed, their associated branches can be safely deleted to keep the repository organized.

To clean up branches:

```bash
# First, do a dry run to see what would be deleted
./scripts/cleanup-branches.sh --dry-run

# Execute the cleanup (requires confirmation)
./scripts/cleanup-branches.sh --execute
```

## License

Licensed under the GNU General Public License v3.0 (GPL-3.0-only). See [LICENSE](LICENSE).

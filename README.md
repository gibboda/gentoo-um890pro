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
- **[Hardware Setup](docs/HARDWARE_SETUP.md)** - BIOS configuration, hardware verification
- **[System Specifications](docs/SYSTEM_SPECS.md)** - Complete hardware specifications
- **[Optimization Guide](docs/OPTIMIZATION_GUIDE.md)** - Performance tuning and optimizations

## Overview

- OS disk: EFI System Partition (FAT32) + Btrfs root with subvolumes (`@`, `@home`, `@var`, `@snapshots`).
- Data disk: single-partition ZFS pool with datasets under `ZFS_MNT_BASE` (default `/data`).
- Init system: `openrc` (default) or `systemd` (controlled by `INIT_SYSTEM`).
- Kernel: installs `gentoo-kernel-bin` when `USE_BINARY_KERNEL=yes`, otherwise builds from source.
- Bootloader: rEFInd (UEFI).
- Desktop: KDE Plasma 6 with Wayland (controlled by `INSTALL_KDE_PLASMA`).
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
  - `sgdisk` (gptfdisk), `wipefs`
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
- `INSTALL_DUAL_KERNEL` — **DEPRECATED**: Now behaves the same as `USE_BINARY_KERNEL=yes`. Binary and source kernels of the same version cannot coexist. For kernel fallback, keep old kernel versions instead.
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

**HMB optimization**: The installer configures udev rules to increase the HMB size from the default 128MB to 256MB for better performance with DRAM-less SSDs. See [OPTIMIZATION_GUIDE.md](docs/OPTIMIZATION_GUIDE.md) for details.

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

### Note: ZFS and binary kernels

The installer uses `sys-fs/zfs-kmod`, which builds kernel modules. If `USE_BINARY_KERNEL=yes` and the module build fails due to missing kernel build trees/config, the script will automatically install `sys-kernel/gentoo-kernel` and retry the ZFS install.

## Versioning

- Current version: [VERSION](VERSION)
- Changelog: [CHANGELOG.md](CHANGELOG.md)
- Bumping versions: [scripts/bump-version.sh](scripts/bump-version.sh)

```bash
chmod +x scripts/bump-version.sh
./scripts/bump-version.sh 0.1.2 "Short summary of changes"
```

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

For more details, see [BRANCH_CLEANUP.md](BRANCH_CLEANUP.md).

## License

Licensed under the GNU General Public License v3.0 (GPL-3.0-only). See [LICENSE](LICENSE).

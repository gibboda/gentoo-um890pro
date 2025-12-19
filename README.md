# Gentoo installer for Minisforum EliteMini UM890 Pro

This repository contains an automated Gentoo bootstrap installer targeted at a Minisforum EliteMini UM890 Pro (UEFI, 2× NVMe). The installer provisions the OS onto one NVMe (Btrfs root + EFI) and a ZFS pool for data/AI models on the other NVMe.

Important: running the installer will irreversibly wipe the selected disks.

Script: [gentoo-um890pro-install.sh](gentoo-um890pro-install.sh)

## Overview

- OS disk: EFI System Partition (FAT32) + Btrfs root with subvolumes (`@`, `@home`, `@var`, `@snapshots`).
- Data disk: single-partition ZFS pool with datasets under `ZFS_MNT_BASE` (default `/data`).
- Init system: `openrc` (default) or `systemd` (controlled by `INIT_SYSTEM`).
- Kernel: installs `gentoo-kernel-bin` when `USE_BINARY_KERNEL=yes`, otherwise builds from source.
- Bootloader: rEFInd (UEFI).
- Desktop: KDE Plasma with Wayland (controlled by `INSTALL_KDE_PLASMA_WAYLAND`).
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
- `DATA_DISK` — device used for ZFS pool (defaults to `/dev/nvme1n1`). Prefer `/dev/disk/by-id/...` paths.
- `ESP_SIZE_MIB` — size of the EFI partition.
- `BTRFS_LABEL`, `ESP_LABEL` — filesystem labels.
- `MNT`, `ESP_MNT`, `ZFS_MNT_BASE` — mountpoints used during install.
- `INIT_SYSTEM` — `openrc` (default) or `systemd`.
- `USE_BINARY_KERNEL` — `yes` to install `gentoo-kernel-bin`.
- `INSTALL_KDE_PLASMA_WAYLAND` — `yes` to install KDE Plasma + Wayland + SDDM.
- `ZPOOL` — name of the ZFS pool created (default `tank`).
- `COMMON_FLAGS` — compile flags written to `make.conf`.
- `TIMEZONE`, `LOCALE` — timezone/locale written into the installed system.

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

## License

Licensed under the GNU General Public License v3.0 (GPL-3.0-only). See [LICENSE](LICENSE).

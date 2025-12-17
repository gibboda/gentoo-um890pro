# Gentoo install for Minisforum EliteMini UM890 Pro

This repository contains an automated Gentoo bootstrap installer targeted at a Minisforum EliteMini UM890 Pro (UEFI, 2× NVMe). The installer provisions the OS onto one NVMe (Btrfs root + EFI) and a ZFS pool for data/AI models on the other NVMe.

**Important Warning:** Running the installer will destroy data on the selected disks. Do not run on a machine with important data unless you have verified backups.

**Script:** [gentoo-um890pro-install.sh](gentoo-um890pro-install.sh)

**High level:**
- Partitions the OS disk into an EFI System Partition (ESP) and a Btrfs root partition.
- Creates Btrfs subvolumes for `@`, `@home`, `@var`, and `@snapshots`.
- Fetches a Gentoo stage3 tarball, prepares a chroot and bootstraps a minimal Gentoo system.
- Installs a kernel (binary option supported), configures `fstab` and GRUB EFI boot.
- Installs ZFS and creates a ZFS pool and datasets (mounted under `/data` by default).
- Prompts interactively for root password and optional non-root user creation.

**Prerequisites (live environment):**
- Boot the installer in UEFI mode.
- Run as `root` with working network.
- Ensure following commands/packages are available in the live environment: `sgdisk` (gptfdisk), `wipefs`, `mkfs.vfat` (dosfstools), `mkfs.btrfs` (btrfs-progs), `tar`, `wget`, `lsblk`, `blkid`, `awk`, `sed`.

**Interactive steps:**
- The script will prompt to confirm disk wipe by typing `WIPE-AND-INSTALL`.
- It will prompt to set the root password and optionally create a non-root user.

**Configurable variables (top of script):**
- `HOSTNAME` — hostname to set in the installed system.
- `OS_DISK` — device for OS (defaults to `/dev/nvme0n1`).
- `DATA_DISK` — device used for ZFS pool (defaults to `/dev/nvme1n1`).
- `ESP_SIZE_MIB` — size of the EFI partition (default 1024 MiB).
- `BTRFS_LABEL`, `ESP_LABEL` — filesystem labels.
- `MNT`, `ESP_MNT`, `ZFS_MNT_BASE` — mountpoint locations used during install.
- `INIT_SYSTEM` — choose `systemd` or `openrc`.
- `USE_BINARY_KERNEL` — `yes` to install `gentoo-kernel-bin` for simplicity.
- `ZPOOL` — name of the ZFS pool created (default `tank`).
- `COMMON_FLAGS` — compile flags placed in `make.conf`.
- `TIMEZONE`, `LOCALE` — timezone and locale set in the installed system.

**Usage:**
1. Boot a Gentoo live environment in UEFI mode and become `root`.
2. Copy or place `gentoo-um890pro-install.sh` on the live system.
3. Edit the variables at the top of the script to match your disks and preferences.
4. Make the script executable and run it:

```bash
chmod +x gentoo-um890pro-install.sh
./gentoo-um890pro-install.sh
```

**Post-install steps (printed by the script):**
- Exit the chroot (if you entered it manually), then:

```bash
umount -R /mnt/gentoo
reboot
```

After reboot, ZFS datasets will be mounted under the configured `ZFS_MNT_BASE` (default `/data`).

**Notes & caveats:**
- The script intentionally uses `sgdisk` and `wipefs` and will reformat the target disks.
- ZFS kernel modules are compiled/managed by Gentoo packages; if using `gentoo-kernel-bin` and zfs-kmod fails to build, switch to a compile-from-source kernel or adjust kernel config.
- The script sets reasonable defaults for compression and Btrfs/ZFS tuning, but review and adjust for your workload (especially `recordsize` for model data).
- If you prefer reproducible installs, replace the stage3 autodiscovery step with a pinned stage3 URL.

**Licensing / attribution:**
- The script is provided as-is. Review and test thoroughly before use.

If you want, I can also:
- Add a brief checklist for preparing the live USB environment.
- Make the script non-interactive with a `--yes`/`--auto` option.
- Add a quick `systemd`/`openrc` verification step after chroot.

**Versioning**

- **Current version:** See the repository `VERSION` file.
- **Changelog:** See `CHANGELOG.md` for versioned entries and release notes.
- **Bumping versions:** A helper script is provided at `scripts/bump-version.sh`.
	Usage:

```bash
chmod +x scripts/bump-version.sh
./scripts/bump-version.sh 0.1.1 "Short summary of changes"
```


The helper will update `VERSION`, prepend a changelog entry under the `Unreleased` section (or append one if missing), and will commit & tag if the repository is a git working tree.

Actions / releases

- **Note:** This repository no longer includes an automated release workflow. Releases, tagging and changelog publishing should be done manually or via an external CI you configure.

If you'd like, I can scaffold a new GitHub Actions release workflow (with an option to use `GITHUB_TOKEN` or an optional `REPO_PAT` secret) — tell me and I will add it.

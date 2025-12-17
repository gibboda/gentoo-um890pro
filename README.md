## Gentoo installer for Minisforum EliteMini UM890 Pro

This repository contains an automated Gentoo bootstrap installer tailored for the
Minisforum EliteMini UM890 Pro. The script provisions a UEFI system with a
Btrfs root filesystem and a ZFS pool for data.

Important: running the installer will irreversibly wipe the selected disks.

### Overview

- Installer script: `gentoo-um890pro-install.sh`
- Target layout: Btrfs root (subvolumes) on `OS_DISK`, ZFS pool on `DATA_DISK`
- Init options: supports `systemd` or `openrc` (controlled via `INIT_SYSTEM`)
- Kernel: can use a binary kernel (`USE_BINARY_KERNEL=yes`) or build from source

### Requirements

- Boot the system in UEFI mode.
- Run from a Gentoo live environment with working network and necessary tools
  installed (`sgdisk`, `wipefs`, `mkfs.vfat`, `mkfs.btrfs`, `jq`, `wget`, `tar`).
- Run the script as root.

### Quick usage

1. Inspect and (optionally) edit configuration variables at the top of
   `gentoo-um890pro-install.sh` (hostname, disks, sizes, timezone, etc.).
2. Boot a Gentoo live environment (UEFI) and ensure networking works.
3. As root, run:

```sh
./gentoo-um890pro-install.sh
```

The script is interactive and requires you to confirm destructive actions by
typing `WIPE-AND-INSTALL`.

### Important configuration variables

- `OS_DISK` — device used for the OS (Btrfs + EFI)
- `DATA_DISK` — device used for the ZFS data pool
- `HOSTNAME` — system hostname
- `INIT_SYSTEM` — `systemd` or `openrc`
- `USE_BINARY_KERNEL` — `yes` to install `gentoo-kernel-bin`, otherwise builds kernel
- `ZPOOL` — ZFS pool name
- `TIMEZONE`, `LOCALE` — locale/timezone settings written into the installed system

All of the above are defined near the top of `gentoo-um890pro-install.sh`.

### What the script does (high level)

- Validates running as root and UEFI boot.
- Confirms disks to be used and requires explicit typed confirmation.
- Partitions `OS_DISK` (EFI + Btrfs) and `DATA_DISK` (single partition for ZFS).
- Formats ESP (FAT32) and the Btrfs partition, creates Btrfs subvolumes, and
  mounts them under `/mnt/gentoo`.
- Downloads a Gentoo stage3 tarball, extracts into the target root, and bind
  mounts `/proc`, `/sys`, and `/dev`.
- Installs base system packages, configures `make.conf`, locales, hostname,
  `fstab`, and installs GRUB for EFI.
- Optionally installs ZFS, creates a pool and datasets under the configured
  mountpoint (default `/data`) and enables relevant services.

### Warnings & tips

- The script is destructive — back up any important data first.
- Prefer specifying stable device paths (for example `/dev/disk/by-id/...`) to
  avoid accidental targeting of the wrong NVMe device.
- Review the `make.conf` and `USE` flags inside the script before running.

### After installation

1. Reboot the machine after the script completes.
2. ZFS datasets created by the installer are mounted under `/data` inside the
   installed system (or the value of `ZFS_MNT_BASE`).

### Contributing / customization

- You can edit the script to change partition sizes, compression settings,
  or add extra packages to install inside `install_base_system()`.

### License

No license is included. Treat this script as sample automation — use at your
own risk and adapt for your environment.
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

Actions permissions & release label format

- **Required permissions:** The release workflow needs `contents: write` permission so the `GITHUB_TOKEN` can create tags and push commits. In GitHub repository settings ensure workflow permissions allow write access for the token. If your organization restricts write access for the default token, create a Personal Access Token (PAT) with `repo` scope and store it in repository secrets (for example `REPO_PAT`), then update the workflow to use that secret when pushing tags.
- **Release label format:** The automated release can be triggered by adding a label to a PR in the form `release: vX.Y.Z` or `release vX.Y.Z`. The workflow parses the label to extract `X.Y.Z`. When labeling a PR with that pattern the workflow will run `scripts/bump-version.sh`, push the commit & tag, and create a GitHub Release using the changelog excerpt, PR title/body and commit list.

- **Release body contents:** The release body includes, when available:
	- The `CHANGELOG.md` excerpt for the released version.
	- The PR title and PR body when triggered from a labeled PR.
	- A short list of commits included in the PR or push (commit subject + short sha).

Note about forked PRs and 'Resource not accessible by integration'

- When a PR comes from a fork, GitHub runs workflows with a read-only token by default for security — the `GITHUB_TOKEN` will not have permission to push tags or write releases from forked PR workflow runs. In that case you will see errors like "Resource not accessible by integration." Options to resolve:
	- Merge the PR then run the release workflow on the `main` branch (push) or use `workflow_dispatch` from a maintainer account.
	- Provide a repository secret `REPO_PAT` (a Personal Access Token with `repo` scope) and set it in repository secrets; the workflow will use it to authenticate pushes/tags when available. Keep this PAT secret and restrict repo permissions appropriately.
	- Alternatively, restrict automatic pushing in PR runs and have the workflow open a release PR or comment prompting a maintainer to trigger the release.

The repository already supports `REPO_PAT` as a fallback in the release workflow; add a PAT to repository secrets if you need releases from fork workflows.

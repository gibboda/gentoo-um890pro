#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Gentoo install bootstrap for Minisforum EliteMini UM890 Pro (UEFI, 2x NVMe)
# OS: Btrfs on Disk0
# Data/AI: ZFS pool on Disk1 (no RAID)
#
# Run from a Gentoo live environment as root, with working network.
#
# WARNING: THIS WILL DESTROY DATA ON THE SELECTED DISKS.
###############################################################################

# ---- CONFIG (edit if needed) ------------------------------------------------
VERSION="2025.1.8"
HOSTNAME="um890-gentoo"

# Pick which disk is OS and which disk is ZFS data.
# TIP: set these to stable /dev/disk/by-id/* paths if possible.
OS_DISK="/dev/nvme0n1"
DATA_DISK="/dev/nvme1n1"

# Partition sizes
ESP_SIZE_MIB="1024"     # 1 GiB EFI System Partition
BTRFS_LABEL="GENTOOROOT"
ESP_LABEL="GENTOO-ESP"

# Mountpoints
MNT="/mnt/gentoo"
ESP_MNT="${MNT}/boot"
ZFS_MNT_BASE="/data"    # ZFS pool mount base inside the installed OS

# Gentoo profile choice (systemd recommended for easier zram-generator)
# "systemd" or "openrc"
INIT_SYSTEM="systemd"

# Use a binary kernel for speed/simplicity (recommended)
USE_BINARY_KERNEL="yes"  # yes/no

# ZFS pool name + datasets
ZPOOL="tank"

# CPU flags: Ryzen 8000/Zen4-ish; use znver4 as a safe default for this class
COMMON_FLAGS="-O2 -pipe -march=znver4"

# Timezone/locale
TIMEZONE="America/Chicago"
LOCALE="en_US.UTF-8 UTF-8"

# -----------------------------------------------------------------------------


need_cmd() { command -v "$1" >/dev/null 2>&1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: run as root."
    exit 1
  fi
}

require_uefi() {
  if [[ ! -d /sys/firmware/efi ]]; then
    echo "ERROR: Not booted in UEFI mode. Reboot the installer in UEFI mode."
    exit 1
  fi
}

confirm_disks() {
  echo "About to WIPE and install to:"
  echo "  OS_DISK   = ${OS_DISK}  (Btrfs root + EFI)"
  echo "  DATA_DISK = ${DATA_DISK} (ZFS pool)"
  echo
  lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE "${OS_DISK}" "${DATA_DISK}" || true
  echo
  read -r -p "Type EXACTLY 'WIPE-AND-INSTALL' to continue: " ans
  [[ "${ans}" == "WIPE-AND-INSTALL" ]] || { echo "Aborted."; exit 1; }
}

stop_mounts() {
  set +e
  umount -R "${MNT}" 2>/dev/null
  zpool export "${ZPOOL}" 2>/dev/null
  swapoff -a 2>/dev/null
  set -e
}

partition_disks() {
  echo "Partitioning disks..."

  need_cmd sgdisk || { echo "ERROR: sgdisk not found (package: gptfdisk)."; exit 1; }
  need_cmd wipefs || { echo "ERROR: wipefs not found."; exit 1; }

  # OS disk: GPT -> ESP + Btrfs
  wipefs -a "${OS_DISK}"
  sgdisk --zap-all "${OS_DISK}"
  sgdisk -n 1:1MiB:+${ESP_SIZE_MIB}MiB -t 1:EF00 -c 1:"${ESP_LABEL}" "${OS_DISK}"
  sgdisk -n 2:0:0              -t 2:8300 -c 2:"${BTRFS_LABEL}" "${OS_DISK}"
  partprobe "${OS_DISK}"

  # DATA disk: GPT -> one big ZFS partition
  wipefs -a "${DATA_DISK}"
  sgdisk --zap-all "${DATA_DISK}"
  # bf00 is "Solaris root" type often used for ZFS on GPT; Linux doesn't require it, but it's tidy.
  sgdisk -n 1:1MiB:0 -t 1:BF00 -c 1:"ZFS-${ZPOOL}" "${DATA_DISK}"
  partprobe "${DATA_DISK}"

  OS_ESP="${OS_DISK}p1"
  OS_ROOT="${OS_DISK}p2"
  DATA_PART="${DATA_DISK}p1"

  echo "OS_ESP  = ${OS_ESP}"
  echo "OS_ROOT = ${OS_ROOT}"
  echo "DATA    = ${DATA_PART}"
}

format_os() {
  echo "Formatting OS disk..."
  need_cmd mkfs.vfat || { echo "ERROR: mkfs.vfat not found."; exit 1; }
  need_cmd mkfs.btrfs || { echo "ERROR: mkfs.btrfs not found."; exit 1; }

  mkfs.vfat -F 32 -n "${ESP_LABEL}" "${OS_ESP}"
  mkfs.btrfs -f -L "${BTRFS_LABEL}" "${OS_ROOT}"
}

mount_btrfs_layout() {
  echo "Creating Btrfs subvolume layout..."
  mkdir -p "${MNT}"
  mount -t btrfs "${OS_ROOT}" "${MNT}"

  # Subvols
  btrfs subvolume create "${MNT}/@"
  btrfs subvolume create "${MNT}/@home"
  btrfs subvolume create "${MNT}/@var"
  btrfs subvolume create "${MNT}/@snapshots"
  umount "${MNT}"

  # Mount with common options
  mount -t btrfs -o noatime,compress=zstd:3,ssd,space_cache=v2,subvol=@ "${OS_ROOT}" "${MNT}"
  mkdir -p "${MNT}/"{home,var,.snapshots,boot}
  mount -t btrfs -o noatime,compress=zstd:3,ssd,space_cache=v2,subvol=@home "${OS_ROOT}" "${MNT}/home"
  mount -t btrfs -o noatime,compress=zstd:3,ssd,space_cache=v2,subvol=@var "${OS_ROOT}" "${MNT}/var"
  mount -t btrfs -o noatime,compress=zstd:3,ssd,space_cache=v2,subvol=@snapshots "${OS_ROOT}" "${MNT}/.snapshots"

  mount "${OS_ESP}" "${ESP_MNT}"
}

fetch_stage3_and_prep() {
  echo "Fetching Stage3 and preparing chroot..."

  need_cmd tar || { echo "ERROR: tar not found."; exit 1; }
  need_cmd wget || { echo "ERROR: wget not found. Install it in the live environment."; exit 1; }

  cd "${MNT}"

  # Use Gentoo's "latest stage3" redirect (works in practice). If your live env lacks SSL CA certs, fix that first.
  # You can swap this out for a pinned URL if you prefer.
  STAGE3_TXT_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-${INIT_SYSTEM}.txt"
  wget -O /tmp/latest-stage3.txt "${STAGE3_TXT_URL}"

  STAGE3_PATH="$(awk '/stage3-amd64/ && $1 ~ /\.tar\.xz$/ {print $1; exit}' /tmp/latest-stage3.txt)"
  [[ -n "${STAGE3_PATH}" ]] || { echo "ERROR: could not parse stage3 path."; exit 1; }

  STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/${STAGE3_PATH}"
  echo "Stage3: ${STAGE3_URL}"
  wget -O stage3.tar.xz "${STAGE3_URL}"

  tar xpf stage3.tar.xz --xattrs-include='*.*' --numeric-owner

  # Basic config + DNS
  mkdir -p "${MNT}/etc/portage"
  cp -L /etc/resolv.conf "${MNT}/etc/resolv.conf"

  # make.conf tuned for this machine class
  cat > "${MNT}/etc/portage/make.conf" <<EOF
COMMON_FLAGS="${COMMON_FLAGS}"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

MAKEOPTS="-j$(nproc)"

# Use your preference; these are reasonable defaults:
FEATURES="parallel-fetch buildpkg"
EMERGE_DEFAULT_OPTS="--ask=n --verbose --keep-going"

# For ZFS + system tools
USE="zfs btrfs -gtk -gnome -kde"
EOF

  # Mount chroot binds
  mount -t proc /proc "${MNT}/proc"
  mount --rbind /sys "${MNT}/sys"
  mount --make-rslave "${MNT}/sys"
  mount --rbind /dev "${MNT}/dev"
  mount --make-rslave "${MNT}/dev"
}

chroot_run() {
  # Run a command inside the chroot
  chroot "${MNT}" /bin/bash -lc "$*"
}

install_base_system() {
  echo "Installing base system inside chroot..."

  # Sync repo
  chroot_run "emerge-webrsync || true"
  chroot_run "emerge --sync"

  # Select profile
  if [[ "${INIT_SYSTEM}" == "systemd" ]]; then
    # Pick a systemd desktop/server profile; choose the first systemd profile found (simple + robust).
    chroot_run "eselect profile list | sed -n '1,200p'"
    chroot_run "PROFILE_ID=\$(eselect profile list | awk '/systemd/ {gsub(/\\[|\\]/,\"\",\$1); print \$1; exit}'); eselect profile set \"\${PROFILE_ID}\""
  else
    chroot_run "eselect profile list | sed -n '1,200p'"
    chroot_run "PROFILE_ID=\$(eselect profile list | awk '/default\\/linux\\/amd64/ && !/systemd/ {gsub(/\\[|\\]/,\"\",\$1); print \$1; exit}'); eselect profile set \"\${PROFILE_ID}\""
  fi

  # Locale/time
  echo "${LOCALE}" > "${MNT}/etc/locale.gen"
  chroot_run "locale-gen"
  chroot_run "eselect locale set en_US.utf8 || true"
  chroot_run "env-update && source /etc/profile"

  echo "${TIMEZONE}" > "${MNT}/etc/timezone"
  chroot_run "emerge --noreplace sys-libs/timezone-data"
  chroot_run "ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime"

  # Hostname + hosts
  echo "${HOSTNAME}" > "${MNT}/etc/hostname"
  cat > "${MNT}/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

  # Firmware + essentials
  chroot_run "emerge sys-kernel/linux-firmware sys-apps/pciutils sys-apps/usbutils app-admin/sudo net-misc/dhcpcd"

  # Filesystems + boot essentials
  chroot_run "emerge sys-fs/btrfs-progs sys-boot/grub sys-boot/efibootmgr"

  # Init-system-specific baseline
  if [[ "${INIT_SYSTEM}" == "systemd" ]]; then
    chroot_run "emerge sys-apps/systemd"
  else
    chroot_run "emerge sys-apps/openrc"
  fi
}

install_kernel() {
  echo "Installing kernel..."

  if [[ "${USE_BINARY_KERNEL}" == "yes" ]]; then
    chroot_run "emerge sys-kernel/gentoo-kernel-bin"
  else
    chroot_run "emerge sys-kernel/gentoo-kernel"
  fi
}

configure_fstab_bootloader() {
  echo "Configuring fstab + GRUB..."

  # Get UUIDs from the live environment (outside chroot) for accuracy
  ESP_UUID="$(blkid -s UUID -o value "${OS_ESP}")"
  ROOT_UUID="$(blkid -s UUID -o value "${OS_ROOT}")"

  cat > "${MNT}/etc/fstab" <<EOF
# <fs>                                 <mountpoint>   <type>  <opts>                                                          <dump/pass>
UUID=${ROOT_UUID}                      /              btrfs   noatime,compress=zstd:3,ssd,space_cache=v2,subvol=@             0 0
UUID=${ROOT_UUID}                      /home          btrfs   noatime,compress=zstd:3,ssd,space_cache=v2,subvol=@home         0 0
UUID=${ROOT_UUID}                      /var           btrfs   noatime,compress=zstd:3,ssd,space_cache=v2,subvol=@var          0 0
UUID=${ROOT_UUID}                      /.snapshots    btrfs   noatime,compress=zstd:3,ssd,space_cache=v2,subvol=@snapshots    0 0
UUID=${ESP_UUID}                       /boot          vfat    noatime                                                          0 2
EOF

  # GRUB config for EFI
  chroot_run "sed -i 's/^#\\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=true/' /etc/default/grub || true"
  chroot_run "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Gentoo --recheck"
  chroot_run "grub-mkconfig -o /boot/grub/grub.cfg"
}

enable_network_and_services() {
  echo "Enabling networking + basic services..."

  if [[ "${INIT_SYSTEM}" == "systemd" ]]; then
    # systemd-networkd + resolved is straightforward in minimal builds
    chroot_run "systemctl enable systemd-networkd systemd-resolved"
    chroot_run "ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || true"

    # Simple DHCP on all ethernet
    mkdir -p "${MNT}/etc/systemd/network"
    cat > "${MNT}/etc/systemd/network/20-wired.network" <<'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
EOF

    # zram (recommended for 96GB systems; reduces swap IO and helps spikes)
    chroot_run "emerge sys-block/zram-generator"
    mkdir -p "${MNT}/etc/systemd"
    cat > "${MNT}/etc/systemd/zram-generator.conf" <<'EOF'
[zram0]
zram-size = ram / 4
compression-algorithm = zstd
swap-priority = 100
EOF
    chroot_run "systemctl enable systemd-zram-setup@zram0.service || true"
  else
    # OpenRC
    chroot_run "rc-update add dhcpcd default"
  fi
}

install_zfs_and_create_pool() {
  echo "Installing ZFS + creating pool/datasets..."

  # ZFS packages
  # NOTE: sys-fs/zfs pulls in kernel module build; with gentoo-kernel-bin this usually works,
  # but if your kernel config/module building fails, you may need to switch to gentoo-kernel or custom kernel.
  chroot_run "emerge sys-fs/zfs sys-fs/zfs-kmod"

  # Ensure ZFS services
  if [[ "${INIT_SYSTEM}" == "systemd" ]]; then
    chroot_run "systemctl enable zfs-import-cache zfs-mount zfs.target"
  else
    chroot_run "rc-update add zfs-import boot"
    chroot_run "rc-update add zfs-mount default"
  fi

  # Create pool and datasets (inside chroot, but uses /dev from bind mount)
  # We set mountpoints under ${ZFS_MNT_BASE}
  chroot_run "zpool create -f -o ashift=12 \
    -O atime=off -O xattr=sa -O acltype=posixacl -O compression=zstd \
    -O normalization=formD -O mountpoint=${ZFS_MNT_BASE} \
    ${ZPOOL} ${DATA_PART}"

  # Datasets
  chroot_run "zfs create -o mountpoint=${ZFS_MNT_BASE}/data ${ZPOOL}/data"
  chroot_run "zfs create -o mountpoint=${ZFS_MNT_BASE}/backup ${ZPOOL}/backup"
  chroot_run "zfs create -o mountpoint=${ZFS_MNT_BASE}/ai-models ${ZPOOL}/ai-models"

  # Nice defaults for big model files/datasets:
  # - recordsize larger can help sequential workloads; keep conservative at 1M
  chroot_run "zfs set recordsize=1M ${ZPOOL}/ai-models"
  chroot_run "zfs set recordsize=1M ${ZPOOL}/data"

  # Cachefile so import works at boot
  chroot_run "zpool set cachefile=/etc/zfs/zpool.cache ${ZPOOL}"

  # Ensure mountpoint exists in rootfs
  mkdir -p "${MNT}${ZFS_MNT_BASE}"
}

finalize_users_passwords() {
  echo "Setting root password and creating a user..."

  chroot_run "passwd"  # interactive

  read -r -p "Create a non-root user now? (y/n): " yn
  if [[ "${yn}" == "y" || "${yn}" == "Y" ]]; then
    read -r -p "Username: " NEWUSER
    chroot_run "useradd -m -G wheel,audio,video -s /bin/bash ${NEWUSER}"
    chroot_run "passwd ${NEWUSER}"
    # Allow wheel sudo
    chroot_run "sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers"
  fi
}

main() {
  require_root
  require_uefi

  echo "gentoo-um890pro-installer version: ${VERSION}"

  for c in lsblk blkid awk sed; do
    need_cmd "$c" || { echo "ERROR: missing required command: $c"; exit 1; }
  done

  confirm_disks
  stop_mounts

  partition_disks
  format_os
  mount_btrfs_layout
  fetch_stage3_and_prep

  install_base_system
  install_kernel
  configure_fstab_bootloader
  enable_network_and_services
  install_zfs_and_create_pool
  finalize_users_passwords

  echo
  echo "============================================================"
  echo "Install complete."
  echo "Next steps:"
  echo "  1) Exit chroot (if you entered manually), then:"
  echo "  2) umount -R ${MNT}"
  echo "  3) reboot"
  echo
  echo "After reboot, ZFS datasets should be mounted under: ${ZFS_MNT_BASE}"
  echo "============================================================"
}

# Globals set during partitioning
OS_ESP=""
OS_ROOT=""
DATA_PART=""

main "$@"

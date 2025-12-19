#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -Eeuo pipefail

# Error context (works best with `set -E`/errtrace enabled above).
on_err() {
  local rc=$?

  # If errexit is currently disabled (e.g. inside a best-effort `set +e` block),
  # do not treat failures as fatal.
  [[ "$-" == *e* ]] || return 0

  local src line cmd
  src="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  line="${BASH_LINENO[0]:-${LINENO}}"
  cmd="${BASH_COMMAND}"
  echo "ERROR: command failed (exit=${rc}) at ${src}:${line}: ${cmd}" >&2
  exit "${rc}"
}
trap on_err ERR

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
VERSION="0.1.3"

# Logging
# By default, the script writes a timestamped log capturing stdout+stderr.
# - Set LOG_ENABLED="no" to disable.
# - Set LOG_FILE to force a specific path (recommended: somewhere persistent).
LOG_ENABLED="yes"   # yes/no
LOG_FILE="~/gentoo-um890pro-install.log"         # e.g. /root/gentoo-um890pro-install.log

# Enable bash xtrace debugging (very verbose). Best used with logging.
DEBUG="no"          # yes/no

# If a repository VERSION file exists alongside this script, prefer it.
# This keeps the script version in sync when run from a cloned checkout,
# while still working when the script is copied standalone.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/VERSION" ]]; then
  VERSION="$(tr -d '\r\n' < "${SCRIPT_DIR}/VERSION")"
fi
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

# Gentoo profile / init system choice
# "openrc" (default; includes an OpenRC zram swap service) or "systemd"
INIT_SYSTEM="openrc"

# Use a binary kernel for speed/simplicity (recommended)
USE_BINARY_KERNEL="yes"  # yes/no

# ZFS pool name + datasets
ZPOOL="tank"

# CPU flags: Ryzen 8000/Zen4-ish; use znver4 as a safe default for this class
COMMON_FLAGS="-O2 -pipe -march=znver4"

# Desktop
INSTALL_KDE_PLASMA_WAYLAND="yes"  # yes/no

# Pure 64-bit (no multilib). The script will try to pick a no-multilib profile.
PURE_64BIT="yes"  # yes/no

# Timezone/locale
TIMEZONE="America/Chicago"
LOCALE="en_US.UTF-8 UTF-8"

# -----------------------------------------------------------------------------


need_cmd() { command -v "$1" >/dev/null 2>&1; }

init_logging() {
  [[ "${LOG_ENABLED}" == "yes" ]] || return 0

  need_cmd tee || { echo "ERROR: tee not found; cannot enable logging." >&2; exit 1; }
  need_cmd date || { echo "ERROR: date not found; cannot enable logging." >&2; exit 1; }

  if [[ -z "${LOG_FILE}" ]]; then
    local ts log_dir
    ts="$(date +%Y%m%d-%H%M%S)"
    log_dir="/root"
    [[ -w "${log_dir}" ]] || log_dir="/tmp"
    LOG_FILE="${log_dir}/gentoo-um890pro-install-${ts}.log"
  fi

  # Ensure the log file can be created.
  touch "${LOG_FILE}" || { echo "ERROR: cannot write log file: ${LOG_FILE}" >&2; exit 1; }

  # Tell the user where the log is, even after we redirect output.
  if [[ -w /dev/tty ]]; then
    echo "Logging to: ${LOG_FILE}" > /dev/tty
  else
    echo "Logging to: ${LOG_FILE}" >&2
  fi

  # Capture both stdout+stderr to the log while still showing output live.
  exec > >(tee -a "${LOG_FILE}") 2>&1
}

enable_debug_trace() {
  [[ "${DEBUG}" == "yes" ]] || return 0

  # Helpful trace prefix: file:line, func, and source line.
  # Note: requires bash.
  export PS4='+(${BASH_SOURCE##*/}:${LINENO}): ${FUNCNAME[0]:-main}: '
  set -x
}

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
  if [[ "${OS_DISK}" == "${DATA_DISK}" ]]; then
    echo "ERROR: OS_DISK and DATA_DISK must be different devices."
    exit 1
  fi
  if [[ ! -b "${OS_DISK}" || ! -b "${DATA_DISK}" ]]; then
    echo "ERROR: One or both disks are not block devices:"
    echo "  OS_DISK=${OS_DISK}"
    echo "  DATA_DISK=${DATA_DISK}"
    exit 1
  fi

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
# Desktop target: KDE Plasma + Wayland
USE="btrfs zfs X wayland kde plasma elogind -gnome"

# GPU/input for this platform
VIDEO_CARDS="amdgpu radeonsi"
INPUT_DEVICES="libinput"

# Prefer pure 64-bit when using a no-multilib profile
ABI_X86="64"
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

chroot_run_maybe() {
  # Like chroot_run, but does not abort the outer script.
  set +e
  chroot "${MNT}" /bin/bash -lc "$*"
  local rc=$?
  set -e
  return $rc
}

install_base_system() {
  echo "Installing base system inside chroot..."

  # Sync repo
  chroot_run "emerge-webrsync || true"
  chroot_run "emerge --sync"

  # Select profile
  # Prefer no-multilib profiles when PURE_64BIT=yes.
  if [[ "${INIT_SYSTEM}" == "systemd" ]]; then
    chroot_run "eselect profile list | sed -n '1,200p'"
    if [[ "${PURE_64BIT}" == "yes" ]]; then
      chroot_run "PROFILE_ID=\$(eselect profile list | awk '/systemd/ && /no-multilib/ {gsub(/\\[|\\]/,\"\",\$1); print \$1; exit}'); if [[ -z \"\${PROFILE_ID}\" ]]; then PROFILE_ID=\$(eselect profile list | awk '/systemd/ {gsub(/\\[|\\]/,\"\",\$1); print \$1; exit}'); fi; [[ -n \"\${PROFILE_ID}\" ]] && eselect profile set \"\${PROFILE_ID}\""
    else
      chroot_run "PROFILE_ID=\$(eselect profile list | awk '/systemd/ {gsub(/\\[|\\]/,\"\",\$1); print \$1; exit}'); [[ -n \"\${PROFILE_ID}\" ]] && eselect profile set \"\${PROFILE_ID}\""
    fi
  else
    chroot_run "eselect profile list | sed -n '1,200p'"
    if [[ "${PURE_64BIT}" == "yes" ]]; then
      chroot_run "PROFILE_ID=\$(eselect profile list | awk '/default\\/linux\\/amd64/ && !/systemd/ && /no-multilib/ {gsub(/\\[|\\]/,\"\",\$1); print \$1; exit}'); if [[ -z \"\${PROFILE_ID}\" ]]; then PROFILE_ID=\$(eselect profile list | awk '/default\\/linux\\/amd64/ && !/systemd/ {gsub(/\\[|\\]/,\"\",\$1); print \$1; exit}'); fi; [[ -n \"\${PROFILE_ID}\" ]] && eselect profile set \"\${PROFILE_ID}\""
    else
      chroot_run "PROFILE_ID=\$(eselect profile list | awk '/default\\/linux\\/amd64/ && !/systemd/ {gsub(/\\[|\\]/,\"\",\$1); print \$1; exit}'); [[ -n \"\${PROFILE_ID}\" ]] && eselect profile set \"\${PROFILE_ID}\""
    fi
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
  chroot_run "emerge sys-fs/btrfs-progs sys-boot/efibootmgr sys-boot/refind"

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
  echo "Configuring fstab + rEFInd..."

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

  # Install rEFInd to the mounted ESP (/boot)
  # refind-install will copy EFI binaries and create a NVRAM entry via efibootmgr.
  chroot_run "refind-install"

  # Provide kernel options for rEFInd's Linux auto-detection.
  # rEFInd looks for refind_linux.conf next to the kernel image in /boot.
  # dist-kernel installs /boot/vmlinuz-* and /boot/initramfs-*.
  cat > "${MNT}/boot/refind_linux.conf" <<EOF
\"Gentoo (Btrfs subvol=@)\"  \"root=UUID=${ROOT_UUID} rootfstype=btrfs rootflags=subvol=@ rw amd_pstate=active\"
EOF
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

    # zram swap via an OpenRC service (keeps Gentoo feeling like Gentoo)
    # Defaults: size=RAM/4, compression=zstd (if supported), high priority.
    cat > "${MNT}/etc/conf.d/zram" <<'EOF'
# /etc/conf.d/zram
# zram swap device configuration

# Set to an absolute size like "24G", or leave empty for auto (RAM/4).
ZRAM_SIZE=""

# Preferred compression algorithm (if supported by the kernel): zstd, lz4, lzo, etc.
ZRAM_COMP_ALGO="zstd"

# Swap priority for zram swap (higher = preferred over disk swap)
ZRAM_SWAP_PRIORITY="100"

# Extra swapon options (rarely needed)
ZRAM_SWAPON_OPTS=""
EOF

    cat > "${MNT}/etc/init.d/zram" <<'EOF'
#!/sbin/openrc-run

description="Compressed RAM-backed swap (zram)"

command="/sbin/modprobe"
command_args="zram num_devices=1"
command_background="no"

depend() {
  need localmount
  after modules
  before swap
}

_mem_kib() {
  awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo
}

_size_bytes_auto() {
  # Default to RAM/4
  local mem_kib
  mem_kib="$(_mem_kib)"
  echo $(( (mem_kib * 1024) / 4 ))
}

_size_bytes_from_human() {
  # Accept forms like 24G, 4096M, 1048576K, or raw bytes.
  local s="$1"
  [[ -z "$s" ]] && return 1

  case "$s" in
    *[Gg]) echo $(( ${s%[Gg]} * 1024 * 1024 * 1024 )) ;;
    *[Mm]) echo $(( ${s%[Mm]} * 1024 * 1024 )) ;;
    *[Kk]) echo $(( ${s%[Kk]} * 1024 )) ;;
    *[0-9]) echo "$s" ;;
    *) return 1 ;;
  esac
}

start_pre() {
  checkpath -d -m 0755 /run
}

start() {
  ebegin "Setting up zram swap"

  if ! /sbin/modprobe zram num_devices=1 2>/dev/null; then
    eend 1 "Failed to load zram module"
    return 1
  fi

  if [[ ! -b /dev/zram0 ]]; then
    eend 1 "/dev/zram0 not present"
    return 1
  fi

  local size_bytes
  if [[ -n "${ZRAM_SIZE:-}" ]]; then
    size_bytes="$(_size_bytes_from_human "${ZRAM_SIZE}")" || size_bytes=""
  fi
  [[ -z "${size_bytes:-}" ]] && size_bytes="$(_size_bytes_auto)"

  # If supported, set compression algorithm.
  if [[ -n "${ZRAM_COMP_ALGO:-}" && -w /sys/block/zram0/comp_algorithm ]]; then
    # Write preferred algo if kernel supports it; otherwise ignore.
    if grep -qw "${ZRAM_COMP_ALGO}" /sys/block/zram0/comp_algorithm 2>/dev/null; then
      echo "${ZRAM_COMP_ALGO}" > /sys/block/zram0/comp_algorithm 2>/dev/null || true
    fi
  fi

  echo "${size_bytes}" > /sys/block/zram0/disksize

  /sbin/mkswap -f /dev/zram0 >/dev/null
  /sbin/swapon -p "${ZRAM_SWAP_PRIORITY:-100}" ${ZRAM_SWAPON_OPTS:-} /dev/zram0

  eend 0
}

stop() {
  ebegin "Tearing down zram swap"
  /sbin/swapoff /dev/zram0 2>/dev/null || true

  # Best-effort reset (kernel-dependent)
  if [[ -w /sys/block/zram0/reset ]]; then
    echo 1 > /sys/block/zram0/reset 2>/dev/null || true
  fi

  eend 0
}
EOF

    chmod +x "${MNT}/etc/init.d/zram"
    chroot_run "rc-update add zram boot"
  fi
}

install_zfs_and_create_pool() {
  echo "Installing ZFS + creating pool/datasets..."

  # ZFS packages
  # NOTE: sys-fs/zfs-kmod builds kernel modules. On some setups (notably when only a binary kernel is installed),
  # module builds can fail due to missing kernel build trees/configs. We attempt a best-effort fallback.
  if ! chroot_run_maybe "emerge sys-fs/zfs sys-fs/zfs-kmod"; then
    if [[ "${USE_BINARY_KERNEL}" == "yes" ]]; then
      echo "WARN: ZFS kernel module build failed with USE_BINARY_KERNEL=yes."
      echo "      Installing a buildable kernel (sys-kernel/gentoo-kernel) and retrying ZFS..."
      chroot_run "emerge sys-kernel/gentoo-kernel"
      chroot_run "emerge sys-fs/zfs sys-fs/zfs-kmod"
    else
      echo "ERROR: Failed to install ZFS kernel modules (sys-fs/zfs-kmod)."
      echo "       Ensure your kernel build tree/config is available, then retry."
      exit 1
    fi
  fi

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

install_kde_plasma_wayland() {
  [[ "${INSTALL_KDE_PLASMA_WAYLAND}" == "yes" ]] || return 0

  echo "Installing KDE Plasma (Wayland)..."

  # Base desktop plumbing
  if [[ "${INIT_SYSTEM}" == "systemd" ]]; then
    chroot_run "emerge sys-apps/dbus net-misc/networkmanager"
    chroot_run "systemctl enable dbus NetworkManager"
  else
    # OpenRC desktops need elogind to provide logind
    chroot_run "emerge sys-apps/dbus sys-auth/elogind net-misc/networkmanager"
    chroot_run "rc-update add dbus default"
    chroot_run "rc-update add elogind default"
    chroot_run "rc-update add NetworkManager default"
  fi

  # Audio/video session stack (Wayland-friendly)
  chroot_run "emerge media-video/pipewire media-video/wireplumber"

  # KDE Plasma + Wayland session + portals
  chroot_run "emerge kde-plasma/plasma-meta kde-plasma/plasma-wayland-session gui-libs/xdg-desktop-portal kde-plasma/xdg-desktop-portal-kde"

  # Display manager
  chroot_run "emerge kde-plasma/sddm"
  if [[ "${INIT_SYSTEM}" == "systemd" ]]; then
    chroot_run "systemctl enable sddm"
  else
    # Use the standard xdm OpenRC service and point it at SDDM
    chroot_run "emerge x11-apps/xdm"
    cat > "${MNT}/etc/conf.d/xdm" <<'EOF'
# /etc/conf.d/xdm
DISPLAYMANAGER="sddm"
EOF
    chroot_run "rc-update add xdm default"
  fi
}

finalize_users_passwords() {
  echo "Setting root password and creating a user..."

  # If DEBUG tracing is enabled, temporarily disable xtrace while we do
  # interactive steps to keep logs cleaner.
  local _trace_was_on="no"
  if [[ "$-" == *x* ]]; then
    _trace_was_on="yes"
    set +x
  fi

  chroot_run "passwd"  # interactive

  read -r -p "Create a non-root user now? (y/n): " yn
  if [[ "${yn}" == "y" || "${yn}" == "Y" ]]; then
    read -r -p "Username: " NEWUSER
    chroot_run "useradd -m -G wheel,audio,video -s /bin/bash ${NEWUSER}"
    chroot_run "passwd ${NEWUSER}"
    # Allow wheel sudo
    chroot_run "sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers"
  fi

  [[ "${_trace_was_on}" == "yes" ]] && set -x
}

main() {
  require_root
  require_uefi

  init_logging
  enable_debug_trace

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
  install_kde_plasma_wayland
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

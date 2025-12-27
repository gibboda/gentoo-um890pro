#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -Eeuo pipefail

# Error context (works best with `set -E`/errtrace enabled above).
on_err() {
  local rc=$?

  # Avoid recursive ERR traps while handling an error.
  trap - ERR
  set +e

  # If errexit is currently disabled (e.g. inside a best-effort `set +e` block),
  # do not treat failures as fatal.
  [[ "$-" == *e* ]] || return 0

  local src line cmd
  src="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  line="${BASH_LINENO[0]:-${LINENO}}"
  cmd="${BASH_COMMAND}"
  echo "ERROR: command failed (exit=${rc}) at ${src}:${line}: ${cmd}" >&2

  if [[ "${LOG_ENABLED:-no}" == "yes" && -n "${LOG_FILE:-}" ]]; then
    echo "ERROR: log file: ${LOG_FILE}" >&2

    # Best-effort: show the last lines from the log to speed up diagnosis.
    if [[ -r "${LOG_FILE}" ]] && command -v tail >/dev/null 2>&1; then
      echo "---- log tail (last 120 lines) ----" >&2
      tail -n 120 "${LOG_FILE}" >&2
      echo "---- end log tail ----" >&2
    fi
  fi
  exit "${rc}"
}
trap on_err ERR

###############################################################################
# Gentoo install bootstrap for Minisforum EliteMini UM890 Pro (UEFI, 2x NVMe)
# Target Hardware:
#   - CPU: AMD Ryzen 9 8945HS
#   - iGPU: AMD Radeon 780M (RDNA 3)
#   - RAM: 2× Crucial 48GB DDR5-5600 (CT48G56C46S5, 96GB total)
#   - Storage: 2× Crucial P3 Plus 4TB NVMe (CT4000P3PSSD8)
# OS: Btrfs on Disk0
# Data/AI: ZFS pool on Disk1 (no RAID)
#
# Run from a Gentoo live environment as root, with working network.
#
# WARNING: THIS WILL DESTROY DATA ON THE SELECTED DISKS.
###############################################################################

# ---- CONFIG (edit if needed) ------------------------------------------------
VERSION="1.0.7"

# Logging
# By default, the script writes a timestamped log capturing stdout+stderr.
# - Set LOG_ENABLED="no" to disable.
# - LOG_FILE defaults to /tmp for Live CD compatibility (typically writable in live environments).
#   You can override by setting LOG_FILE environment variable before running the script
#   (e.g., export LOG_FILE=/mnt/usb/install.log for persistent storage).
LOG_ENABLED="yes"   # yes/no
LOG_FILE="${LOG_FILE:-/tmp/gentoo-um890pro-install.log}"

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

# Use a binary kernel for speed/simplicity (recommended for initial installation)
# You can switch to source kernel later using: sudo switch-to-source-kernel
USE_BINARY_KERNEL="yes"  # yes/no

# ZFS pool name + datasets
ZPOOL="tank"

# CPU flags: Ryzen 8000/Zen4-ish; use znver4 as a safe default for this class
COMMON_FLAGS="-O2 -pipe -march=znver4"

# Desktop and AI workloads
INSTALL_KDE_PLASMA="yes"  # yes/no
INSTALL_BLENDER="yes"     # yes/no - Install Blender 3D creation suite
INSTALL_COMFYUI="yes"     # yes/no - Install ComfyUI for AI image generation (includes SDXL support)
INSTALL_ROCM="yes"        # yes/no - Install ROCm for AMD GPU compute

# Pure 64-bit (no multilib). The script will try to pick a no-multilib profile.
PURE_64BIT="yes"  # yes/no

# Safe dual-kernel setup: installs BOTH a stable binary kernel AND a custom source kernel
# with unique LOCALVERSION to avoid collisions. Provides maximum fallback safety.
# - Kernel A: gentoo-kernel-bin (stable fallback, never modified)
# - Kernel B: gentoo-sources with LOCALVERSION=-um890-tuned (custom optimized)
# Both kernels will have unique uname -r, separate /lib/modules, and versioned /boot artifacts.
INSTALL_DUAL_KERNEL="no"  # yes/no - Set to "yes" for safe dual-kernel installation

# Enable snapshot management for Btrfs
ENABLE_SNAPSHOTS="yes"  # yes/no - Set up automated snapshot management

# Timezone/locale
TIMEZONE="America/Chicago"
LOCALE="en_US.UTF-8 UTF-8"

# -----------------------------------------------------------------------------


need_cmd() { command -v "$1" >/dev/null 2>&1; }

init_logging() {
  [[ "${LOG_ENABLED}" == "yes" ]] || return 0

  need_cmd tee || { echo "ERROR: tee not found; cannot enable logging." >&2; exit 1; }
  need_cmd date || { echo "ERROR: date not found; cannot enable logging." >&2; exit 1; }

  # Strip accidental surrounding quotes if the user pasted them.
  if [[ -n "${LOG_FILE}" ]]; then
    # Strip one layer of surrounding quotes (single or double), if present.
    if [[ ( "${LOG_FILE:0:1}" == "\"" && "${LOG_FILE: -1}" == "\"" ) || ( "${LOG_FILE:0:1}" == "'" && "${LOG_FILE: -1}" == "'" ) ]]; then
      LOG_FILE="${LOG_FILE:1:${#LOG_FILE}-2}"
    fi
  fi

  if [[ -z "${LOG_FILE}" ]]; then
    local ts log_dir
    ts="$(date +%Y%m%d-%H%M%S)"
    log_dir="/root"
    [[ -w "${log_dir}" ]] || log_dir="/tmp"
    LOG_FILE="${log_dir}/gentoo-um890pro-install-${ts}.log"
  fi

  # Ensure the log directory exists and the log file can be created.
  # If the configured location isn't writable/valid, fall back to /tmp.
  local log_dir
  log_dir="$(dirname -- "${LOG_FILE}")"
  if ! mkdir -p "${log_dir}" 2>/dev/null || ! touch "${LOG_FILE}" 2>/dev/null; then
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    LOG_FILE="/tmp/gentoo-um890pro-install-${ts}.log"
    mkdir -p "$(dirname -- "${LOG_FILE}")" || { echo "ERROR: cannot create fallback log directory for: ${LOG_FILE}" >&2; exit 1; }
    touch "${LOG_FILE}" || { echo "ERROR: cannot write fallback log file: ${LOG_FILE}" >&2; exit 1; }
    if [[ -w /dev/tty ]]; then
      echo "WARN: configured LOG_FILE was not writable; using fallback: ${LOG_FILE}" > /dev/tty
    else
      echo "WARN: configured LOG_FILE was not writable; using fallback: ${LOG_FILE}" >&2
    fi
  fi

  # Tell the user where the log is, even after we redirect output.
  if [[ -w /dev/tty ]]; then
    echo "Logging to: ${LOG_FILE}" > /dev/tty
  else
    echo "Logging to: ${LOG_FILE}" >&2
  fi

  # Capture both stdout+stderr to the log while still showing output live.
  # Some minimal/live environments can lack working process-substitution
  # plumbing (e.g., /dev/fd). Test if it works before using it.
  
  # Test if process substitution works in this environment
  local _ps_works="yes"
  if ! { echo test | tee >(cat >/dev/null) >/dev/null; } 2>/dev/null; then
    _ps_works="no"
  fi
  
  if [[ "${_ps_works}" == "yes" ]]; then
    # Use process substitution with tee for live output + logging
    exec > >(tee -a "${LOG_FILE}") 2>&1
  else
    # Process substitution not available - use file-only logging
    exec >>"${LOG_FILE}" 2>&1
    if [[ -w /dev/tty ]]; then
      echo "WARN: live logging via tee/process-substitution not available; logging to file only: ${LOG_FILE}" > /dev/tty
    else
      echo "WARN: live logging via tee/process-substitution not available; logging to file only: ${LOG_FILE}" >&2
    fi
  fi
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
# Desktop target: KDE Plasma 6 + Wayland
# Note: opengl is required globally for qtbase when wayland is enabled (REQUIRED_USE: wayland? ( opengl ))
USE="btrfs zfs X wayland kde plasma elogind opengl -gnome"

# GPU/input for this platform
VIDEO_CARDS="amdgpu radeonsi"
INPUT_DEVICES="libinput"

# Prefer pure 64-bit when using a no-multilib profile
ABI_X86="64"

# Python targets - set globally to avoid USE flag conflicts
# Support both python3_12 and python3_13 to prevent slot conflicts
# Multiple targets allow packages with different Python versions to coexist
PYTHON_TARGETS="python3_12 python3_13"
PYTHON_SINGLE_TARGET="python3_12"
EOF

  # Configure Portage to keep old kernel versions for backup/fallback
  # This prevents emerge --depclean from removing old kernels automatically.
  # Kernel preservation is handled via the dedicated Portage set below.

  # Add configuration to preserve multiple kernel slots
  mkdir -p "${MNT}/etc/portage/sets"
  cat > "${MNT}/etc/portage/sets/kernels" <<'EOF'
# Kernel preservation set
# Add specific kernel versions here to prevent removal
# Example (edit after installation):
# sys-kernel/gentoo-kernel-bin:6.12.58
# sys-kernel/gentoo-kernel:6.13.0
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
  local cmd="$*"
  echo ">>> chroot: ${cmd}"
  
  # Flush any pending output to log before running the command
  sync 2>/dev/null || true

  if [[ ! -d "${MNT}" ]]; then
    echo "ERROR: chroot root not found: ${MNT}" >&2
    exit 1
  fi
  if [[ ! -x "${MNT}/bin/bash" ]]; then
    echo "ERROR: ${MNT}/bin/bash not found; stage3 may not be extracted." >&2
    exit 1
  fi

  chroot "${MNT}" /bin/bash -lc "${cmd}"
  
  # Log completion for long-running commands
  echo ">>> chroot completed: ${cmd}"
}

chroot_run_maybe() {
  # Like chroot_run, but does not abort the outer script.
  local cmd="$*"
  echo ">>> chroot(maybe): ${cmd}"
  
  # Flush any pending output to log before running the command
  sync 2>/dev/null || true
  
  set +e
  chroot "${MNT}" /bin/bash -lc "${cmd}"
  local rc=$?
  set -e
  
  # Log completion status
  if [[ ${rc} -eq 0 ]]; then
    echo ">>> chroot(maybe) completed successfully: ${cmd}"
  else
    echo ">>> chroot(maybe) failed with exit code ${rc}: ${cmd}"
  fi
  
  return $rc
}

install_base_system() {
  echo "Installing base system inside chroot..."

  # Sync repo
  chroot_run "emerge-webrsync || true"
  chroot_run "emerge --sync"

  # Select profile
  # Prefer no-multilib profiles when PURE_64BIT=yes.
  # Optimize by: 1) Getting profile list once 2) Processing selection logic in single chroot call
  if [[ "${INIT_SYSTEM}" == "systemd" ]]; then
    if [[ "${PURE_64BIT}" == "yes" ]]; then
      chroot_run "eselect profile list | sed -n '1,200p' && PROFILE_ID=\$(eselect profile list | awk '/systemd/ && /no-multilib/ {gsub(/\\[|\\]/,\"\",\$1); print \$1; exit}'); if [[ -z \"\${PROFILE_ID}\" ]]; then PROFILE_ID=\$(eselect profile list | awk '/systemd/ {gsub(/\\[|\\]/,\"\",\$1); print \$1; exit}'); fi; [[ -n \"\${PROFILE_ID}\" ]] && eselect profile set \"\${PROFILE_ID}\""
    else
      chroot_run "eselect profile list | sed -n '1,200p' && PROFILE_ID=\$(eselect profile list | awk '/systemd/ {gsub(/\\[|\\]/,\"\",\$1); print \$1; exit}'); [[ -n \"\${PROFILE_ID}\" ]] && eselect profile set \"\${PROFILE_ID}\""
    fi
  else
    if [[ "${PURE_64BIT}" == "yes" ]]; then
      chroot_run "eselect profile list | sed -n '1,200p' && PROFILE_ID=\$(eselect profile list | awk '/default\\/linux\\/amd64/ && !/systemd/ && /no-multilib/ {gsub(/\\[|\\]/,\"\",\$1); print \$1; exit}'); if [[ -z \"\${PROFILE_ID}\" ]]; then PROFILE_ID=\$(eselect profile list | awk '/default\\/linux\\/amd64/ && !/systemd/ {gsub(/\\[|\\]/,\"\",\$1); print \$1; exit}'); fi; [[ -n \"\${PROFILE_ID}\" ]] && eselect profile set \"\${PROFILE_ID}\""
    else
      chroot_run "eselect profile list | sed -n '1,200p' && PROFILE_ID=\$(eselect profile list | awk '/default\\/linux\\/amd64/ && !/systemd/ {gsub(/\\[|\\]/,\"\",\$1); print \$1; exit}'); [[ -n \"\${PROFILE_ID}\" ]] && eselect profile set \"\${PROFILE_ID}\""
    fi
  fi

  # Locale/time - combine locale commands into single chroot call
  echo "${LOCALE}" > "${MNT}/etc/locale.gen"
  chroot_run "locale-gen && eselect locale set en_US.utf8 || true && env-update && source /etc/profile"

  # Timezone - combine timezone setup into single chroot call
  echo "${TIMEZONE}" > "${MNT}/etc/timezone"
  chroot_run "emerge --noreplace sys-libs/timezone-data && ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime"

  # Hostname + hosts
  echo "${HOSTNAME}" > "${MNT}/etc/hostname"
  cat > "${MNT}/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

  # Configure package.license for linux-firmware
  mkdir -p "${MNT}/etc/portage/package.license"
  cat > "${MNT}/etc/portage/package.license/linux-firmware" <<EOF
# Accept licenses for firmware packages
sys-kernel/linux-firmware linux-fw-redistributable no-source-code
EOF

  # Accept testing keyword for linux-firmware (required for AMD Radeon 780M RDNA3 support)
  # The UM890 Pro's Radeon 780M (gfx1103) requires recent firmware for proper GPU functionality
  mkdir -p "${MNT}/etc/portage/package.accept_keywords"
  cat > "${MNT}/etc/portage/package.accept_keywords/linux-firmware" <<EOF
# AMD Radeon 780M (RDNA3, gfx1103) requires latest firmware for GPU acceleration
sys-kernel/linux-firmware ~amd64
EOF

  # Configure package.use for installkernel based on selected init system
  mkdir -p "${MNT}/etc/portage/package.use"
  
  # Python packages - Global Python target configuration
  # This prevents infinite loop of USE flag changes across the entire system
  cat > "${MNT}/etc/portage/package.use/python" <<EOF
# Global Python target configuration
# All Python packages support both python3_12 and python3_13 to prevent slot conflicts
# Multiple targets allow packages with different Python versions to coexist
# This includes packages pulled in by system dependencies (Sphinx, docutils, etc.)

# Apply both python3_12 and python3_13 targets to all Python packages globally
# This is the most robust solution to prevent USE flag conflicts
dev-python/* python_targets_python3_12 python_targets_python3_13
EOF
  
  # Btrfs tools with man pages (requires Sphinx, which will use configured Python targets)
  cat > "${MNT}/etc/portage/package.use/btrfs" <<EOF
# Enable man pages for btrfs-progs (requires Sphinx documentation system)
sys-fs/btrfs-progs man
EOF
  
  if [[ "${INIT_SYSTEM}" == "systemd" ]]; then
    cat > "${MNT}/etc/portage/package.use/installkernel" <<EOF
# Enable systemd integration for installkernel
sys-kernel/installkernel systemd
EOF
  else
    cat > "${MNT}/etc/portage/package.use/installkernel" <<EOF
# Enable dracut for initramfs generation
sys-kernel/installkernel dracut
EOF
  fi

  # Configure package.use for Qt base packages (modular approach for better maintainability)
  # Separate configuration files allow independent management of different component groups
  
  # Qt 6 Core Packages - Graphics Backend Configuration
  # qtbase uses OpenGL + Vulkan to satisfy KDE Plasma 6 components that require Vulkan (e.g., kinfocenter)
  # This configuration keeps Wayland-required OpenGL while aligning Vulkan across Qt 6 modules
  cat > "${MNT}/etc/portage/package.use/qt-base" <<EOF
# Qt 6 base library with OpenGL support for AMD RDNA3 graphics
# Note: OpenGL is required when wayland USE flag is enabled (REQUIRED_USE: wayland? ( opengl ))
# Vulkan is enabled to match KDE Plasma requirements (kinfocenter, kscreen, qtquick3d, qtmultimedia)
dev-qt/qtbase libproxy icu cups opengl vulkan
dev-qt/qt5compat qml icu
app-text/xmlto text
sys-libs/zlib minizip
EOF

  # Qt 6 Additional Modules
  cat > "${MNT}/etc/portage/package.use/qt-modules" <<EOF
# Qt multimedia for audio/video in KDE applications
dev-qt/qtmultimedia qml vulkan
# Qt Declarative/QML engine must match qtbase Vulkan setting to avoid slot conflicts
dev-qt/qtdeclarative vulkan
# Qt Quick 3D renderer matches qtbase Vulkan setting
dev-qt/qtquick3d vulkan
EOF

  # KDE Frameworks - Core libraries used by KDE Plasma
  cat > "${MNT}/etc/portage/package.use/kde-frameworks" <<EOF
# KDE Frameworks dependencies
kde-frameworks/kconfig dbus qml
kde-frameworks/kcoreaddons dbus
kde-frameworks/prison qml
kde-frameworks/sonnet qml
dev-libs/qcoro dbus
# Image formats (required by kscreen): enable AVIF support
kde-frameworks/kimageformats avif
EOF

  # KDE Plasma - Desktop environment specific settings
  cat > "${MNT}/etc/portage/package.use/kde-plasma" <<EOF
# KDE Plasma 6 + Wayland desktop environment
kde-plasma/kwin lock
kde-plasma/kwin-x11 lock
net-wireless/wpa_supplicant dbus
EOF

  # Audio and Video - PipeWire multimedia stack for KDE Plasma
  cat > "${MNT}/etc/portage/package.use/audio" <<EOF
# PipeWire audio/video server for low-latency multimedia
media-video/pipewire sound-server pipewire-alsa extra gstreamer
media-video/wireplumber elogind
EOF

  # Graphics and Display - Hardware acceleration and Wayland support
  cat > "${MNT}/etc/portage/package.use/graphics" <<EOF
# AMD Radeon 780M iGPU support (UM890 Pro integrated graphics)
# Enable DRM for direct rendering and hardware acceleration
x11-libs/libdrm video_cards_radeon
# Wayland display server support with libei for input emulation
x11-base/xwayland libei
# Mesa with Vulkan and OpenCL support for AMD RDNA3
media-libs/mesa vulkan video_cards_radeon
# freetype harfbuzz needed by the pango stack pulled by PipeWire/GStreamer
media-libs/freetype harfbuzz
EOF

  # Disable ModemManager in NetworkManager (no modem present in UM890 Pro)
  cat > "${MNT}/etc/portage/package.use/networkmanager" <<EOF
# Disable ModemManager support - no modem hardware present
net-misc/networkmanager -modemmanager
EOF

  # Blender 3D - Graphics application requiring OpenGL and Vulkan
  # This configuration ensures Blender has all necessary graphics backends and features
  cat > "${MNT}/etc/portage/package.use/blender" <<EOF
# Blender 3D creation suite with full feature set
# GPU Rendering: opengl vulkan cycles embree openpgl openimagedenoise oslray
# 3D Libraries: openvdb bullet opensubdiv tbb
# Media Formats: openexr ffmpeg fftw jack jpeg2k openimageio
# Import/Export: alembic collada
# UI/Documentation: color-management man nls
# Utilities: pugixml potrace
media-gfx/blender opengl vulkan cycles openexr openvdb bullet ffmpeg fftw jack jpeg2k openimageio \
  openpgl opensubdiv oslray embree tbb color-management man nls alembic collada \
  openimagedenoise pugixml potrace

# Blender dependencies - ensure proper graphics support
media-libs/openimageio opengl
# Note: opencl enables OpenCL rendering; opengl for viewport; ptex for texture mapping
media-libs/opensubdiv opencl opengl ptex tbb
dev-cpp/tbb malloc-proxy
media-libs/opencolorio opengl
media-libs/embree tbb
sci-libs/openvdb abi8-compat blosc numpy openvdb-compression python zlib

# Additional media libraries for Blender
media-video/ffmpeg x264 x265 vpx opus mp3 theora vorbis
media-libs/mesa vulkan
EOF

  # If Blender is not requested, remove the Blender-specific package.use file
  if [[ "${INSTALL_BLENDER:-no}" != "yes" ]]; then
    rm -f /mnt/gentoo/etc/portage/package.use/blender
  fi

  # ROCm - AMD GPU compute for AI workloads on Radeon 780M iGPU
  # Configure ROCm with support for the UM890 Pro's integrated graphics
  cat > "${MNT}/etc/portage/package.use/rocm" <<EOF
# ROCm for AMD Radeon 780M iGPU (gfx1103 architecture)
# Enable OpenCL and HIP for GPU compute acceleration
dev-libs/rocm-opencl-runtime asan clang lto
dev-libs/rocr-runtime asan
dev-libs/roct-thunk-interface asan
dev-util/hip clang

# LLVM/Clang for ROCm
sys-devel/llvm rocm
sys-devel/clang rocm

# Mesa with ROCm support
media-libs/mesa opencl

# Python packages for AI/ML
dev-python/torch rocm
dev-python/torchvision rocm
EOF

  # ROCm package accept keywords
  # ROCm testing packages are required for AMD Radeon 780M (gfx1103) support
  # The Radeon 780M uses RDNA3 architecture which needs recent ROCm versions
  cat > "${MNT}/etc/portage/package.accept_keywords/rocm" <<EOF
# ROCm packages (testing required for AMD Radeon 780M gfx1103 support)
dev-libs/rocm-opencl-runtime ~amd64
dev-libs/rocr-runtime ~amd64
dev-libs/roct-thunk-interface ~amd64
dev-util/hip ~amd64
dev-util/rocminfo ~amd64
EOF

  # If ROCm is not requested, remove the ROCm-specific files
  if [[ "${INSTALL_ROCM:-no}" != "yes" ]]; then
    rm -f "${MNT}/etc/portage/package.use/rocm"
    rm -f "${MNT}/etc/portage/package.accept_keywords/rocm"
  fi

  # ComfyUI-specific USE flags (if needed)
  # Note: Python targets are configured globally in package.use/python
  # When ComfyUI is being installed, create a placeholder file for potential ComfyUI-specific USE flags
  if [[ "${INSTALL_COMFYUI:-no}" == "yes" ]]; then
    cat > "${MNT}/etc/portage/package.use/comfyui" <<EOF
# ComfyUI-specific USE flags
# Python targets are configured globally in package.use/python
# This file is a placeholder for potential ComfyUI-specific USE flags and is only created when ComfyUI is installed
EOF
  fi
  
  # Firmware, essentials, filesystems + boot essentials (split for better error visibility)
  echo "Installing firmware and essential system packages..."
  echo "This may take several minutes (especially sys-kernel/linux-firmware which is a large package)..."

  echo "Installing linux-firmware..."
  chroot_run "emerge sys-kernel/linux-firmware"

  echo "Installing system utilities..."
  chroot_run "emerge sys-apps/pciutils sys-apps/usbutils app-admin/sudo net-misc/dhcpcd"

  echo "Installing filesystem and boot tools..."
  chroot_run "emerge sys-fs/btrfs-progs sys-boot/efibootmgr sys-boot/refind"

  if [[ "${INIT_SYSTEM}" == "systemd" ]]; then
    echo "Installing systemd..."
    chroot_run "emerge sys-apps/systemd"
  else
    echo "Installing openrc..."
    chroot_run "emerge sys-apps/openrc"
  fi
}

install_kernel() {
  echo "Installing kernel..."

  # Safe dual-kernel installation strategy:
  # - Kernel A (stable fallback): gentoo-kernel-bin - installed first, never modified
  # - Kernel B (tuned experimental): gentoo-sources with LOCALVERSION - custom build
  # Both kernels have unique uname -r, separate /lib/modules, and versioned /boot artifacts

  if [[ "${INSTALL_DUAL_KERNEL:-no}" == "yes" ]]; then
    echo "================================================================================"
    echo "Safe Dual-Kernel Installation"
    echo "================================================================================"
    echo "Installing two independent kernels for maximum safety:"
    echo "  - Kernel A: Binary dist-kernel (stable fallback)"
    echo "  - Kernel B: Custom source kernel with LOCALVERSION (tuned for UM890)"
    echo
    
    # ========== KERNEL A: Stable Binary Fallback ==========
    echo "Step 1/3: Installing Kernel A (stable binary fallback)..."
    echo "  Package: sys-kernel/gentoo-kernel-bin"
    echo "  Purpose: Stable fallback kernel, never modified by this script"
    echo
    
    # Install binary kernel first - this gives us a working fallback
    chroot_run "emerge sys-kernel/gentoo-kernel-bin"
    
    # Get the kernel version that was just installed
    KERNEL_A_VERSION=$(chroot_run "eselect kernel list 2>/dev/null | grep -oP 'gentoo-kernel-bin-\K[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo ''")
    if [[ -z "${KERNEL_A_VERSION}" ]]; then
      # Fallback: try to get version from /boot files
      KERNEL_A_VERSION=$(chroot_run "ls /boot/vmlinuz-*-gentoo-dist 2>/dev/null | head -n1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || echo 'unknown'")
    fi
    echo "  Installed: gentoo-kernel-bin-${KERNEL_A_VERSION}"
    echo "  Note: Kernel A initramfs was generated automatically and will NOT be touched again"
    echo
    
    # ========== KERNEL B: Custom Source Kernel ==========
    echo "Step 2/3: Installing Kernel B (custom tuned kernel)..."
    echo "  Package: sys-kernel/gentoo-sources"
    echo "  LOCALVERSION: -um890-tuned"
    echo "  Purpose: Optimized kernel for UM890 Pro hardware"
    echo
    
    # Install gentoo-sources for manual kernel build
    chroot_run "emerge sys-kernel/gentoo-sources"
    
    # Configure dracut to generate per-kernel initramfs with versioned names
    # This prevents collisions between Kernel A and Kernel B
    mkdir -p "${MNT}/etc/dracut.conf.d"
    cat > "${MNT}/etc/dracut.conf.d/10-versioned.conf" <<'EOF'
# Per-kernel initramfs configuration
# Generate initramfs-<kernel-version>.img for each kernel
# This prevents collisions between binary and source kernels

# Use versioned naming: initramfs-<kernel-version>.img
# Do NOT use generic names like "initramfs.img"
hostonly="yes"
hostonly_cmdline="no"
compress="zstd"

# Early microcode for AMD
early_microcode="yes"

# Essential modules for UM890 Pro
# Note: ZFS module will be added automatically if sys-fs/zfs is installed
add_drivers+=" amdgpu btrfs nvme "
add_dracutmodules+=" kernel-modules rootfs-block btrfs resume "

# Ensure unique naming per kernel version
# dracut will automatically append kernel version to output filename
EOF

    # Set LOCALVERSION for Kernel B to ensure unique uname -r
    # This is the key to avoiding /lib/modules and /boot collisions
    echo "  Setting LOCALVERSION=-um890-tuned for unique kernel identification..."
    
    # Get the latest gentoo-sources version and verify it was found
    KERNEL_B_BASE_VERSION=$(chroot_run "eselect kernel list 2>/dev/null | grep 'gentoo-sources' | grep -oP 'gentoo-sources-\K[0-9]+\.[0-9]+\.[0-9]+(-r[0-9]+)?' | head -n1 || echo ''")
    
    if [[ -z "${KERNEL_B_BASE_VERSION}" ]]; then
      echo "ERROR: Failed to detect gentoo-sources version. Ensure gentoo-sources is installed."
      exit 1
    fi
    
    echo "  Base version: ${KERNEL_B_BASE_VERSION}"
    
    # Select gentoo-sources for configuration
    if ! chroot_run "eselect kernel set gentoo-sources-${KERNEL_B_BASE_VERSION}"; then
      echo "ERROR: Failed to select gentoo-sources-${KERNEL_B_BASE_VERSION}. Check eselect kernel list."
      exit 1
    fi
    
    # Configure the kernel with LOCALVERSION
    # Copy binary kernel config as base, then set LOCALVERSION
    cat > "${MNT}/tmp/kernel-config.sh" <<'KCONFIG'
#!/bin/bash
set -Eeuo pipefail

cd /usr/src/linux

# Start with the binary kernel config as a base (it's known to work)
# Find the most recent config file in /boot
LATEST_CONFIG=$(ls -t /boot/config-* 2>/dev/null | head -n1 || echo "")

if [[ -n "${LATEST_CONFIG}" && -f "${LATEST_CONFIG}" ]]; then
    cp "${LATEST_CONFIG}" .config
    echo "Using binary kernel config as base: ${LATEST_CONFIG}"
else
    # Fallback to default config
    make defconfig
    echo "Using default config as base (no existing config found)"
fi

# Set LOCALVERSION to make this kernel unique using scripts/config
# This ensures uname -r differs from Kernel A and handles existing values properly
if [[ -x scripts/config ]]; then
    scripts/config --set-str CONFIG_LOCALVERSION "-um890-tuned"
    scripts/config --disable CONFIG_LOCALVERSION_AUTO
else
    # Fallback if scripts/config not available
    sed -i '/^CONFIG_LOCALVERSION/d' .config
    sed -i '/^CONFIG_LOCALVERSION_AUTO/d' .config
    echo 'CONFIG_LOCALVERSION="-um890-tuned"' >> .config
    echo '# CONFIG_LOCALVERSION_AUTO is not set' >> .config
fi

# Update config for new options
make olddefconfig

# Verify LOCALVERSION is set
if grep -q "CONFIG_LOCALVERSION=\"-um890-tuned\"" .config; then
    echo "LOCALVERSION successfully set to -um890-tuned"
else
    echo "ERROR: Failed to set LOCALVERSION" >&2
    exit 1
fi

echo "Kernel configuration complete for Kernel B"
KCONFIG
    
    chmod +x "${MNT}/tmp/kernel-config.sh"
    chroot_run "/tmp/kernel-config.sh"
    
    # Build Kernel B with the custom config
    echo "  Building Kernel B (this will take 30-60 minutes)..."
    echo "  Note: Kernel B will have unique version suffix: -um890-tuned"
    
    # Build kernel, modules, and install
    # Use per-kernel initramfs generation (not --regenerate-all)
    cat > "${MNT}/tmp/kernel-build.sh" <<'KBUILD'
#!/bin/bash
set -Eeuo pipefail

cd /usr/src/linux

# Build kernel and modules
echo "Building kernel..."
make -j$(nproc)

echo "Installing modules..."
make modules_install

# Get kernel version with LOCALVERSION
KVER=$(make kernelrelease)
echo "Kernel version: ${KVER}"

# Install kernel to /boot with versioned name
echo "Installing kernel to /boot/vmlinuz-${KVER}..."
install -m 0644 arch/x86/boot/bzImage "/boot/vmlinuz-${KVER}"
install -m 0644 .config "/boot/config-${KVER}"
install -m 0644 System.map "/boot/System.map-${KVER}"

# Generate initramfs for THIS kernel only (not --regenerate-all)
echo "Generating initramfs for kernel ${KVER}..."
dracut --force --hostonly --kver "${KVER}" "/boot/initramfs-${KVER}.img"

# Verify artifacts were created with correct names
echo "Verifying installation..."
ls -lh "/boot/vmlinuz-${KVER}" "/boot/initramfs-${KVER}.img" "/lib/modules/${KVER}"

echo "Kernel B installation complete"
echo "  vmlinuz: /boot/vmlinuz-${KVER}"
echo "  initramfs: /boot/initramfs-${KVER}.img"
echo "  modules: /lib/modules/${KVER}"
KBUILD
    
    chmod +x "${MNT}/tmp/kernel-build.sh"
    chroot_run "/tmp/kernel-build.sh"
    
    # Clean up temporary scripts
    rm -f "${MNT}/tmp/kernel-config.sh" "${MNT}/tmp/kernel-build.sh"
    
    # ========== VERIFICATION ==========
    echo
    echo "Step 3/3: Verifying dual-kernel installation..."
    
    # Verify both kernels are present with unique names
    echo "  Checking /boot artifacts for installed kernels..."
    # Use specific version variables to verify exact files installed
    chroot_run "echo 'Kernel A:' && ls -lh /boot/vmlinuz-${KERNEL_A_VERSION}-gentoo-dist /boot/initramfs-${KERNEL_A_VERSION}-gentoo-dist.img /boot/config-${KERNEL_A_VERSION}-gentoo-dist 2>/dev/null || echo 'WARNING: Kernel A files not found'" || true
    chroot_run "echo 'Kernel B:' && ls -lh /boot/vmlinuz-*-um890-tuned /boot/initramfs-*-um890-tuned.img /boot/config-*-um890-tuned 2>/dev/null || echo 'WARNING: Kernel B files not found'" || true
    
    echo "  Checking /lib/modules directories for installed kernels..."
    chroot_run "echo 'Kernel A:' && ls -ld /lib/modules/${KERNEL_A_VERSION}-gentoo-dist 2>/dev/null || echo 'WARNING: Kernel A modules not found'" || true
    chroot_run "echo 'Kernel B:' && ls -ld /lib/modules/*-um890-tuned 2>/dev/null || echo 'WARNING: Kernel B modules not found'" || true
    
    echo
    echo "================================================================================"
    echo "Dual-kernel installation complete!"
    echo "================================================================================"
    echo
    echo "Kernel A (stable fallback):"
    echo "  - Package: gentoo-kernel-bin-${KERNEL_A_VERSION}"
    echo "  - Located: /boot/vmlinuz-${KERNEL_A_VERSION}-gentoo-dist"
    echo "  - initramfs: /boot/initramfs-${KERNEL_A_VERSION}-gentoo-dist.img"
    echo "  - Purpose: Always bootable fallback kernel"
    echo
    echo "Kernel B (tuned experimental):"
    echo "  - Package: gentoo-sources-${KERNEL_B_BASE_VERSION}"
    echo "  - Located: /boot/vmlinuz-${KERNEL_B_BASE_VERSION}-um890-tuned"
    echo "  - initramfs: /boot/initramfs-${KERNEL_B_BASE_VERSION}-um890-tuned.img"
    echo "  - Purpose: Optimized kernel for UM890 Pro"
    echo
    echo "Both kernels will appear in rEFInd boot menu for easy selection."
    echo "Default boot: rEFInd will auto-select the most recent kernel."
    echo "================================================================================"
    
  elif [[ "${USE_BINARY_KERNEL}" == "yes" ]]; then
    # Single binary kernel installation (original behavior)
    echo "Installing single binary kernel (gentoo-kernel-bin)..."
    chroot_run "emerge sys-kernel/gentoo-kernel-bin"
  else
    # Single source kernel installation (original behavior)
    echo "Installing single source kernel (gentoo-kernel)..."
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
\"Gentoo (Snapshot Recovery)\"  \"root=UUID=${ROOT_UUID} rootfstype=btrfs rootflags=subvol=@snapshots/@-snapshot-latest rw amd_pstate=active\"
EOF

  # Configure rEFInd for snapshot support
  cat > "${MNT}/boot/EFI/refind/refind.conf" <<EOF
# rEFInd configuration for Gentoo with snapshot support
timeout 20
use_nvram false
dont_scan_files shim.efi,shim-fedora.efi,shimx64.efi,PreLoader.efi,TextMode.efi,ebounce.efi,GraphicsConsole.efi,MokManager.efi,HashTool.efi,HashTool-signed.efi,bootmgr.efi,fb{arch}.efi
scanfor manual,external
scan_all_linux_kernels true

# Enable touchscreen and mouse support
enable_touch
enable_mouse

# Menu appearance
banner boot/EFI/refind/icons/banner.png
selection_big boot/EFI/refind/icons/selection_big.png
selection_small boot/EFI/refind/icons/selection_small.png
EOF
}

enable_network_and_services() {
  echo "Enabling networking + basic services..."

  if [[ "${INIT_SYSTEM}" == "systemd" ]]; then
    # systemd-networkd + resolved is straightforward in minimal builds
    # Combine service enable and symlink in single chroot call
    chroot_run "systemctl enable systemd-networkd systemd-resolved && ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || true"

    # Simple DHCP on all ethernet
    mkdir -p "${MNT}/etc/systemd/network"
    cat > "${MNT}/etc/systemd/network/20-wired.network" <<'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
EOF

    # zram (recommended for 96GB systems; reduces swap IO and helps spikes)
    mkdir -p "${MNT}/etc/systemd"
    cat > "${MNT}/etc/systemd/zram-generator.conf" <<'EOF'
[zram0]
zram-size = ram / 4
compression-algorithm = zstd
swap-priority = 100
EOF
    # Batch emerge and service enable
    chroot_run "emerge sys-block/zram-generator && systemctl enable systemd-zram-setup@zram0.service || true"
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
    # Combine rc-update calls
    chroot_run "rc-update add zfs-import boot && rc-update add zfs-mount default"
  fi

  # Create pool and datasets (inside chroot, but uses /dev from bind mount)
  # We set mountpoints under ${ZFS_MNT_BASE}
  # Note: Batched into single chroot call for performance (reduces overhead).
  # The && chain ensures any failure stops the sequence (errexit behavior).
  chroot_run "zpool create -f -o ashift=12 \
    -O atime=off -O xattr=sa -O acltype=posixacl -O compression=zstd \
    -O normalization=formD -O mountpoint=${ZFS_MNT_BASE} \
    ${ZPOOL} ${DATA_PART} && \
    zfs create -o mountpoint=${ZFS_MNT_BASE}/data ${ZPOOL}/data && \
    zfs create -o mountpoint=${ZFS_MNT_BASE}/backup ${ZPOOL}/backup && \
    zfs create -o mountpoint=${ZFS_MNT_BASE}/ai-models ${ZPOOL}/ai-models && \
    zfs set recordsize=1M ${ZPOOL}/ai-models && \
    zfs set recordsize=1M ${ZPOOL}/data && \
    zpool set cachefile=/etc/zfs/zpool.cache ${ZPOOL}"

  # Ensure mountpoint exists in rootfs
  mkdir -p "${MNT}${ZFS_MNT_BASE}"
}

install_kde_plasma() {
  [[ "${INSTALL_KDE_PLASMA}" == "yes" ]] || return 0

  echo "Installing KDE Plasma 6 (with Wayland support)..."

  # Base desktop plumbing
  if [[ "${INIT_SYSTEM}" == "systemd" ]]; then
    # Batch emerge and service enable in single chroot call
    chroot_run "emerge sys-apps/dbus net-misc/networkmanager && systemctl enable dbus NetworkManager"
  else
    # OpenRC desktops need elogind to provide logind
    # Batch emerge and rc-update in single chroot call
    chroot_run "emerge sys-apps/dbus sys-auth/elogind net-misc/networkmanager && rc-update add dbus default && rc-update add elogind default && rc-update add NetworkManager default"
  fi

  # Audio/video session stack + KDE Plasma + Display manager
  # Note: Batched emerge for performance. All packages are inter-related desktop components,
  # so if any fails, the desktop won't work anyway. The && chain ensures proper error handling.
  if [[ "${INIT_SYSTEM}" == "systemd" ]]; then
    chroot_run "emerge media-video/pipewire media-video/wireplumber kde-plasma/plasma-meta kde-plasma/plasma-login-sessions sys-apps/xdg-desktop-portal kde-plasma/xdg-desktop-portal-kde x11-misc/sddm kde-plasma/sddm-kcm && systemctl enable sddm"
  else
    chroot_run "emerge media-video/pipewire media-video/wireplumber kde-plasma/plasma-meta kde-plasma/plasma-login-sessions sys-apps/xdg-desktop-portal kde-plasma/xdg-desktop-portal-kde x11-misc/sddm kde-plasma/sddm-kcm x11-apps/xdm"
    cat > "${MNT}/etc/conf.d/xdm" <<'EOF'
# /etc/conf.d/xdm
DISPLAYMANAGER="sddm"
EOF
    chroot_run "rc-update add xdm default"
  fi
}

install_blender() {
  [[ "${INSTALL_BLENDER}" == "yes" ]] || return 0

  echo "Installing Blender 3D creation suite..."
  echo "This will take 1-2 hours depending on CPU performance and network speed."
  echo "Blender will be configured with OpenGL and Vulkan support for GPU rendering."

  # Blender has many dependencies and takes time to compile
  # We install it separately to provide clear progress feedback
  chroot_run "emerge media-gfx/blender"
  
  echo "Blender installation complete."
  
  # Create Blender Cycles iGPU optimization config
  mkdir -p "${MNT}/etc/skel/.config/blender"
  cat > "${MNT}/etc/skel/.config/blender/cycles-igpu-config.py" <<'EOF'
# Blender Cycles iGPU optimization for AMD Radeon 780M
# Place this in ~/.config/blender/X.X/scripts/startup/ to auto-load

import bpy

def setup_cycles_igpu():
    # Get scene preferences
    prefs = bpy.context.preferences
    cycles_prefs = prefs.addons['cycles'].preferences
    
    # Configure for iGPU rendering
    cycles_prefs.compute_device_type = 'HIP'  # Use HIP for AMD
    
    # Enable GPU rendering
    for device in cycles_prefs.devices:
        if device.type == 'HIP':
            device.use = True
    
    # Scene optimization for UMA
    scene = bpy.context.scene
    scene.cycles.device = 'GPU'
    
    # Reduce memory pressure for UMA systems
    scene.cycles.tile_size = 256  # Smaller tiles for shared memory
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.01
    
    # Enable memory optimizations
    scene.render.use_persistent_data = True
    scene.cycles.debug_use_spatial_splits = True
    
    print("Cycles configured for AMD Radeon 780M iGPU (UMA optimized)")

# Auto-run on Blender startup
if __name__ == "__main__":
    setup_cycles_igpu()
EOF
}

install_rocm() {
  [[ "${INSTALL_ROCM}" == "yes" ]] || return 0

  echo "Installing ROCm for AMD GPU compute..."
  echo "This enables GPU acceleration for AI/ML workloads on the Radeon 780M iGPU."
  
  # Install ROCm runtime and OpenCL
  chroot_run "emerge dev-libs/rocm-opencl-runtime dev-util/rocminfo"
  
  # Configure ROCm for gfx1103 (Radeon 780M)
  cat > "${MNT}/etc/profile.d/rocm.sh" <<'EOF'
# ROCm environment configuration for AMD Radeon 780M
export ROCM_PATH=/usr
export HIP_PATH=/usr
export HSA_OVERRIDE_GFX_VERSION=11.0.3
export GPU_DEVICE_ORDINAL=0
export HIP_VISIBLE_DEVICES=0
EOF
  
  chmod +x "${MNT}/etc/profile.d/rocm.sh"
  
  echo "ROCm installation complete."
}

install_comfyui_and_sdxl() {
  [[ "${INSTALL_COMFYUI}" == "yes" ]] || return 0

  echo "Installing ComfyUI and SDXL models..."
  
  # Install Python and dependencies
  chroot_run "emerge dev-lang/python:3.12 dev-python/pip dev-vcs/git"
  
  # Create ComfyUI installation directory on ZFS
  mkdir -p "${MNT}${ZFS_MNT_BASE}/ai-models/ComfyUI"
  
  # Install ComfyUI (will be cloned by user after first boot)
  cat > "${MNT}/usr/local/bin/setup-comfyui" <<'EOF'
#!/bin/bash
# ComfyUI setup script for UMA-optimized Stable Diffusion XL

set -e

COMFYUI_DIR="/data/ai-models/ComfyUI"
MODELS_DIR="${COMFYUI_DIR}/models"

echo "Setting up ComfyUI for AMD Radeon 780M with UMA optimizations..."

# Clone ComfyUI if not present
if [[ ! -d "${COMFYUI_DIR}" ]]; then
    git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}"
fi

cd "${COMFYUI_DIR}"

# Create virtual environment
python3.12 -m venv venv
source venv/bin/activate

# Install dependencies with ROCm support
pip install --upgrade pip
pip install torch torchvision --index-url https://download.pytorch.org/whl/rocm5.7
pip install -r requirements.txt

# Create UMA-optimized config
cat > extra_model_paths.yaml <<'YAML'
# ComfyUI model paths
comfyui:
    base_path: /data/ai-models/ComfyUI/
    checkpoints: models/checkpoints/
    vae: models/vae/
    loras: models/loras/
    upscale_models: models/upscale_models/
YAML

# Create launch script with UMA optimizations
cat > launch-comfyui-uma.sh <<'LAUNCH'
#!/bin/bash
# Launch ComfyUI with UMA memory optimizations

export PYTORCH_HIP_ALLOC_CONF=max_split_size_mb:512
export TORCH_HOME=/data/ai-models/torch-cache
export HF_HOME=/data/ai-models/huggingface-cache

# UMA-specific: limit VRAM to leave room for system
export HSA_OVERRIDE_GFX_VERSION=11.0.3
export ROCM_PATH=/usr

cd "$(dirname "$0")"
source venv/bin/activate

# Run with memory optimization flags
python main.py \
    --lowvram \
    --preview-method auto \
    --use-split-cross-attention \
    --disable-xformers \
    --listen 0.0.0.0 \
    --port 8188
LAUNCH

chmod +x launch-comfyui-uma.sh

echo "ComfyUI setup complete!"
echo "To download SDXL models, run:"
echo "  cd ${MODELS_DIR}/checkpoints"
echo "  wget https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors"
echo ""
echo "To start ComfyUI:"
echo "  cd ${COMFYUI_DIR}/ComfyUI"
echo "  ./launch-comfyui-uma.sh"
EOF

  chmod +x "${MNT}/usr/local/bin/setup-comfyui"
  
  # Create UMA-optimized workflow template
  mkdir -p "${MNT}/etc/skel/comfyui-workflows"
  cat > "${MNT}/etc/skel/comfyui-workflows/sdxl-uma-workflow.json" <<'EOF'
{
  "workflow": {
    "name": "SDXL UMA Optimized",
    "description": "Memory-efficient SDXL workflow for UMA systems with 96GB RAM",
    "nodes": {
      "checkpoint_loader": {
        "type": "CheckpointLoaderSimple",
        "params": {
          "ckpt_name": "sd_xl_base_1.0.safetensors"
        },
        "optimizations": {
          "use_fp16": true,
          "attention_slicing": true,
          "vae_slicing": true
        }
      },
      "sampler_settings": {
        "steps": 20,
        "cfg": 7.0,
        "sampler_name": "euler_a",
        "scheduler": "normal",
        "denoise": 1.0
      },
      "memory_optimizations": {
        "enable_sequential_cpu_offload": false,
        "enable_vae_slicing": true,
        "enable_attention_slicing": true,
        "use_pytorch_cross_attention": true
      }
    },
    "notes": "Optimized for AMD Radeon 780M iGPU with 96GB shared memory (UMA)"
  }
}
EOF
  
  echo "ComfyUI and SDXL setup scripts installed."
  echo "Run 'setup-comfyui' after first boot to complete installation."
}

setup_snapshot_management() {
  [[ "${ENABLE_SNAPSHOTS}" == "yes" ]] || return 0
  
  echo "Setting up Btrfs snapshot management..."
  
  # Install snapper for snapshot management
  chroot_run "emerge app-backup/snapper"
  
  # Create snapper config for root subvolume
  cat > "${MNT}/etc/snapper/configs/root" <<'EOF'
# Snapper configuration for root filesystem
SUBVOLUME="/"
FSTYPE="btrfs"
NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="10"
NUMBER_LIMIT_IMPORTANT="10"
TIMELINE_CREATE="yes"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="5"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="0"
TIMELINE_LIMIT_MONTHLY="0"
TIMELINE_LIMIT_YEARLY="0"
EOF

  # Create snapshot management script
  cat > "${MNT}/usr/local/bin/manage-snapshots" <<'EOF'
#!/bin/bash
# Btrfs snapshot management for Gentoo rollback

set -e

BTRFS_ROOT="/mnt/btrfs-root"
SNAPSHOTS_DIR="${BTRFS_ROOT}/@snapshots"

usage() {
    echo "Usage: $0 {create|list|rollback|cleanup}"
    echo "  create   - Create a new snapshot"
    echo "  list     - List available snapshots"
    echo "  rollback - Rollback to a snapshot"
    echo "  cleanup  - Remove old snapshots"
    exit 1
}

ensure_mounted() {
    if ! mountpoint -q "${BTRFS_ROOT}"; then
        mkdir -p "${BTRFS_ROOT}"
        mount -t btrfs /dev/disk/by-label/GENTOOROOT "${BTRFS_ROOT}"
    fi
}

create_snapshot() {
    ensure_mounted
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local snapshot_name="@-snapshot-${timestamp}"
    
    echo "Creating snapshot: ${snapshot_name}"
    mkdir -p "${SNAPSHOTS_DIR}"
    btrfs subvolume snapshot -r "${BTRFS_ROOT}/@" "${SNAPSHOTS_DIR}/${snapshot_name}"
    
    # Update latest symlink (use atomic, non-directory replacement)
    ln -snf "${snapshot_name}" "${SNAPSHOTS_DIR}/@-snapshot-latest"
    
    echo "Snapshot created successfully"
}

list_snapshots() {
    ensure_mounted
    echo "Available snapshots:"
    btrfs subvolume list "${BTRFS_ROOT}" | grep "@-snapshot-"
}

rollback_snapshot() {
    ensure_mounted
    echo "Available snapshots:"
    list_snapshots
    echo ""
    read -r -p "Enter snapshot name to rollback to: " snapshot_name
    
    if [[ ! -d "${SNAPSHOTS_DIR}/${snapshot_name}" ]]; then
        echo "ERROR: Snapshot not found: ${snapshot_name}"
        exit 1
    fi
    
    echo "Rolling back to: ${snapshot_name}"
    echo "This will require a reboot. Continue? (yes/no)"
    read confirm
    
    if [[ "${confirm}" != "yes" ]]; then
        echo "Rollback cancelled"
        exit 0
    fi
    
    # Rename current @ to @-old
    mv "${BTRFS_ROOT}/@" "${BTRFS_ROOT}/@-old-$(date +%Y%m%d-%H%M%S)"
    
    # Create new @ from snapshot
    btrfs subvolume snapshot "${SNAPSHOTS_DIR}/${snapshot_name}" "${BTRFS_ROOT}/@"
    
    echo "Rollback complete. Please reboot."
}

cleanup_snapshots() {
    ensure_mounted
    echo "Cleaning up old snapshots (keeping last 10)..."
    
    # Get list of snapshots sorted by date
    local snapshots=($(ls -1t "${SNAPSHOTS_DIR}" | grep "@-snapshot-" | tail -n +11))
    
    for snapshot in "${snapshots[@]}"; do
        echo "Removing: ${snapshot}"
        btrfs subvolume delete "${SNAPSHOTS_DIR}/${snapshot}"
    done
    
    echo "Cleanup complete"
}

case "${1:-}" in
    create)
        create_snapshot
        ;;
    list)
        list_snapshots
        ;;
    rollback)
        rollback_snapshot
        ;;
    cleanup)
        cleanup_snapshots
        ;;
    *)
        usage
        ;;
esac
EOF

  chmod +x "${MNT}/usr/local/bin/manage-snapshots"
  
  # Create automated snapshot service
  if [[ "${INIT_SYSTEM}" == "systemd" ]]; then
    cat > "${MNT}/etc/systemd/system/btrfs-snapshot.service" <<'EOF'
[Unit]
Description=Create Btrfs snapshot before system updates
Before=package-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/manage-snapshots create

[Install]
WantedBy=multi-user.target
EOF

    cat > "${MNT}/etc/systemd/system/btrfs-snapshot.timer" <<'EOF'
[Unit]
Description=Daily Btrfs snapshot

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

    chroot_run "systemctl enable btrfs-snapshot.timer"
  else
    # OpenRC cron job
    cat > "${MNT}/etc/cron.daily/btrfs-snapshot" <<'EOF'
#!/bin/bash
/usr/local/bin/manage-snapshots create
/usr/local/bin/manage-snapshots cleanup
EOF
    chmod +x "${MNT}/etc/cron.daily/btrfs-snapshot"
  fi
  
  echo "Snapshot management configured."
}

setup_ml_boot_selector() {
  echo "Setting up ML-based boot target selection system..."
  
  # Create boot selection ML script
  cat > "${MNT}/usr/local/bin/ml-boot-selector" <<'EOF'
#!/usr/bin/env python3
"""
Machine Learning Boot Target Selector
Analyzes system state and hardware adaptation to select optimal boot target
"""

import os
import sys
import json
import subprocess
from datetime import datetime
from pathlib import Path

BOOT_LOG = "/var/log/ml-boot-selector.log"
STATE_FILE = "/var/lib/ml-boot-selector/state.json"
BOOT_TARGETS = {
    "current": {
        "name": "Gentoo Linux (Current)",
        "priority": 100,
        "kernel": "/vmlinuz",
        "description": "Latest system state"
    },
    "snapshot": {
        "name": "Gentoo Linux (Snapshot - Safe Boot)",
        "priority": 50,
        "kernel": "/vmlinuz",
        "description": "Last known good snapshot"
    },
    "fallback": {
        "name": "Gentoo Linux (Binary Kernel Fallback)",
        "priority": 25,
        "kernel": "/vmlinuz-bin",
        "description": "Binary kernel fallback"
    }
}

def log_message(message):
    """Log message to boot selector log"""
    timestamp = datetime.now().isoformat()
    with open(BOOT_LOG, "a") as f:
        f.write(f"[{timestamp}] {message}\n")

def get_system_health():
    """Analyze system health metrics"""
    health = {
        "boot_count": 0,
        "last_boot_success": True,
        "hardware_errors": 0,
        "memory_errors": 0,
        "disk_errors": 0
    }
    
    # Check boot count
    try:
        result = subprocess.run(["journalctl", "--list-boots"], 
                              capture_output=True, text=True, check=True)
        health["boot_count"] = len(result.stdout.strip().split("\n"))
    except:
        pass
    
    # Check for hardware errors in dmesg
    try:
        result = subprocess.run(["dmesg", "-l", "err,warn"], 
                              capture_output=True, text=True, check=True)
        errors = result.stdout.lower()
        if "memory" in errors or "ram" in errors:
            health["memory_errors"] += errors.count("error")
        if "disk" in errors or "nvme" in errors:
            health["disk_errors"] += errors.count("error")
        health["hardware_errors"] = errors.count("error")
    except:
        pass
    
    return health

def load_boot_history():
    """Load historical boot data"""
    Path(STATE_FILE).parent.mkdir(parents=True, exist_ok=True)
    
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, "r") as f:
            return json.load(f)
    return {"boots": [], "failures": 0, "last_target": "current"}

def save_boot_history(history):
    """Save boot history"""
    with open(STATE_FILE, "w") as f:
        json.dump(history, f, indent=2)

def select_boot_target():
    """Use ML heuristics to select best boot target"""
    health = get_system_health()
    history = load_boot_history()
    
    log_message(f"System health: {health}")
    log_message(f"Boot history: failures={history['failures']}, last={history['last_target']}")
    
    # Decision logic
    if history["failures"] >= 3:
        # Multiple failures - use fallback kernel
        selected = "fallback"
        log_message("Selected: fallback (multiple boot failures detected)")
    elif health["hardware_errors"] > 10 or health["memory_errors"] > 5:
        # Hardware issues - use snapshot
        selected = "snapshot"
        log_message("Selected: snapshot (hardware errors detected)")
    elif health["disk_errors"] > 0:
        # Disk issues - use snapshot
        selected = "snapshot"
        log_message("Selected: snapshot (disk errors detected)")
    else:
        # System healthy - use current
        selected = "current"
        log_message("Selected: current (system healthy)")
    
    # Update history
    history["boots"].append({
        "timestamp": datetime.now().isoformat(),
        "target": selected,
        "health": health
    })
    
    # Keep only last 100 boots
    if len(history["boots"]) > 100:
        history["boots"] = history["boots"][-100:]
    
    history["last_target"] = selected
    save_boot_history(history)
    
    return BOOT_TARGETS[selected]

def main():
    """Main entry point"""
    try:
        target = select_boot_target()
        print(json.dumps(target, indent=2))
        log_message(f"Recommended boot target: {target['name']}")
        return 0
    except Exception as e:
        log_message(f"ERROR: {str(e)}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
EOF

  chmod +x "${MNT}/usr/local/bin/ml-boot-selector"
  
  # Create integration with rEFInd
  cat > "${MNT}/usr/local/bin/update-refind-default" <<'EOF'
#!/bin/bash
# Update rEFInd default based on ML selector recommendation

ML_RESULT=$(/usr/local/bin/ml-boot-selector)
RECOMMENDED=$(echo "${ML_RESULT}" | jq -r '.name')

echo "ML Boot Selector recommends: ${RECOMMENDED}"

# This could update rEFInd config or just log for manual intervention
# For now, we log the recommendation
logger -t refind-ml "Recommended boot: ${RECOMMENDED}"
EOF

  chmod +x "${MNT}/usr/local/bin/update-refind-default"
  
  echo "ML boot selector configured."
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

configure_nvme_optimizations() {
  echo "Configuring NVMe optimizations for Crucial P3 Plus..."
  
  # Create udev rules for NVMe optimization
  cat > "${MNT}/etc/udev/rules.d/60-nvme-crucial-p3.rules" <<'EOF'
# NVMe optimization for Crucial P3 Plus CT4000P3PSSD8
# The P3 Plus uses HMB (Host Memory Buffer) instead of onboard DRAM.
# NOTE: HMB size is managed via NVMe admin commands (e.g. nvme-cli), not via
#       non-portable sysfs attributes. This udev rule only applies generic
#       queue tunables and does not attempt to change HMB size.

# Generic NVMe optimizations
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/nr_requests}="1024"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/read_ahead_kb}="2048"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/max_sectors_kb}="1024"
EOF

  # Configure NVMe power management
  cat > "${MNT}/etc/modprobe.d/nvme.conf" <<'EOF'
# NVMe power management for Crucial P3 Plus
# Balance between performance and power efficiency
options nvme_core default_ps_max_latency_us=5500
EOF

  echo "NVMe optimizations configured."
}

create_kernel_switch_helper() {
  echo "Creating kernel switch helper script..."
  
  # Ensure target directory exists for the helper script
  mkdir -p "${MNT}/usr/local/bin"
  # Create helper script for switching from binary to source kernel
  cat > "${MNT}/usr/local/bin/switch-to-source-kernel" <<'EOF'
#!/bin/bash
# Helper script to switch from gentoo-kernel-bin to gentoo-kernel (source)
# This allows users to optimize their kernel after initial installation

set -e

if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root" 
   exit 1
fi

echo "================================================================================"
echo "Kernel Switch Helper: Binary to Source (with Backup)"
echo "================================================================================"
echo
echo "This script will help you switch from the binary kernel (gentoo-kernel-bin)"
echo "to the source kernel (gentoo-kernel) for optimization and customization."
echo
echo "IMPORTANT NOTES:"
echo "  1. The binary and source kernels CANNOT coexist in the same slot"
echo "  2. Old kernel versions will be kept automatically for backup/fallback"
echo "  3. Building the source kernel will take 30-60 minutes"
echo "  4. Your current kernel configuration will be preserved"
echo "  5. You can boot into old kernels from the rEFInd boot menu"
echo
echo "Current kernel packages:"
emerge --search sys-kernel/gentoo-kernel 2>/dev/null | grep -E '^\* sys-kernel/gentoo-kernel$|^[[:space:]]*Latest version available:|^[[:space:]]*Installed versions:' || true
echo

read -r -p "Do you want to proceed? (yes/no): " confirm
if [[ "${confirm}" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

echo
echo "================================================================================"
echo "Step 1: Recording current kernel for backup..."
echo "================================================================================"

# Get current kernel version to preserve
CURRENT_KERNEL=$(eselect kernel show | grep -oP 'linux-\K[0-9]+\.[0-9]+\.[0-9]+.*' || echo "unknown")
echo "Current kernel version: ${CURRENT_KERNEL}"

# Paths for kernel preservation set and lock file
KERNEL_SET_FILE="/etc/portage/sets/kernels"
KERNEL_SET_LOCK="${KERNEL_SET_FILE}.lock"

# Find installed binary kernel packages (prefer qlist, but fall back to eix/emerge if needed)
if command -v qlist >/dev/null 2>&1; then
    BINARY_KERNELS=$(qlist -ICv sys-kernel/gentoo-kernel-bin 2>/dev/null || echo "")
elif command -v eix >/dev/null 2>&1; then
    # eix fallback: list installed package atoms matching sys-kernel/gentoo-kernel-bin
    BINARY_KERNELS=$(eix -I --only-names sys-kernel/gentoo-kernel-bin 2>/dev/null || echo "")
elif command -v emerge >/dev/null 2>&1; then
    # emerge fallback: parse search output to extract the package atom
    BINARY_KERNELS=$(emerge -s sys-kernel/gentoo-kernel-bin 2>/dev/null | awk '/^\* sys-kernel\/gentoo-kernel-bin/ {print $2}' || echo "")
else
    BINARY_KERNELS=""
fi
if [[ -n "${BINARY_KERNELS}" ]]; then
    echo "Binary kernels installed:"
    echo "${BINARY_KERNELS}"

    # Add to kernel preservation set
    echo
    echo "Adding current binary kernel(s) to preservation set..."

    # Use a lockfile if flock is available to avoid concurrent modifications.
    if command -v flock >/dev/null 2>&1; then
        flock_cmd=(flock -w 10 "${KERNEL_SET_LOCK}")
    else
        flock_cmd=()
    fi

    # Run the update under the (optional) lock, avoiding duplicate entries and
    # only adding a comment when at least one new kernel is preserved.
    "${flock_cmd[@]}" bash -c '
        set -Eeuo pipefail
        kernel_set_file="$1"
        shift

        # Ensure the set file exists
        touch "${kernel_set_file}"

        added_any=false
        for pkg in "$@"; do
            # Skip empty lines
            [[ -z "${pkg}" ]] && continue

            # Only add package if it is not already present
            if ! grep -qxF "${pkg}" "${kernel_set_file}"; then
                if [ "${added_any}" = false ]; then
                    echo "# Auto-added by switch-to-source-kernel on $(date)" >> "${kernel_set_file}"
                    added_any=true
                fi
                echo "${pkg}" >> "${kernel_set_file}"
                echo "  Preserved: ${pkg}"
            else
                echo "  Already preserved: ${pkg}"
            fi
        done
    ' bash "${KERNEL_SET_FILE}" ${BINARY_KERNELS}
fi

echo
echo "================================================================================"
echo "Step 2: Installing source kernel (this will take 30-60 minutes)..."
echo "================================================================================"
echo "Note: The binary kernel in the SAME slot will be automatically replaced."
echo "      Old binary kernels in DIFFERENT slots are preserved as backup."
echo

# Install source kernel - this will replace binary kernel in the same slot
if [[ -t 0 ]]; then
    # Interactive session: keep emerge confirmation prompt for safety
    emerge --ask sys-kernel/gentoo-kernel
else
    # Non-interactive session: avoid --ask to prevent hanging automated runs
    echo "Non-interactive mode detected; emerging sys-kernel/gentoo-kernel without --ask." >&2
    emerge sys-kernel/gentoo-kernel
fi

echo
echo "================================================================================"
echo "Step 3: Verifying kernel installation..."
echo "================================================================================"

# Show installed kernels
echo "Installed kernel packages:"
qlist -ICv sys-kernel/gentoo-kernel sys-kernel/gentoo-kernel-bin 2>/dev/null || \
    eix -I --only-names sys-kernel/gentoo-kernel sys-kernel/gentoo-kernel-bin 2>/dev/null || \
    emerge -s sys-kernel/gentoo-kernel | grep "Installed versions"

echo
echo "Available kernel sources:"
eselect kernel list

echo
echo "================================================================================"
echo "Step 4: Kernel configuration (optional customization)"
echo "================================================================================"
echo
read -r -p "Do you want to customize the kernel config now? (y/n): " customize
if [[ "${customize}" == "y" || "${customize}" == "Y" ]]; then
    cd /usr/src/linux
    make menuconfig
    echo
    echo "Rebuilding kernel with custom configuration..."
    emerge --config sys-kernel/gentoo-kernel
fi

echo
echo "================================================================================"
echo "Kernel switch complete!"
echo "================================================================================"
echo
echo "Next steps:"
echo "  1. REBOOT to test the new kernel"
echo "  2. After verifying the new kernel works, old kernels are still available"
echo "  3. Boot menu (rEFInd) will show all installed kernel versions"
echo
echo "Backup kernels:"
echo "  - Old kernel versions are preserved automatically"
echo "  - View preserved kernels: cat /etc/portage/sets/kernels"
echo "  - Boot old kernels from rEFInd boot menu if needed"
echo
echo "To customize kernel later:"
echo "  cd /usr/src/linux"
echo "  make menuconfig"
echo "  emerge --config sys-kernel/gentoo-kernel"
echo
echo "To manage kernel versions:"
echo "  - List: eselect kernel list"
echo "  - Keep multiple versions for fallback"
echo "  - Remove old versions: emerge --deselect sys-kernel/gentoo-kernel:<version>"
echo "================================================================================"
EOF

  chmod +x "${MNT}/usr/local/bin/switch-to-source-kernel"
  
  echo "Kernel switch helper created at /usr/local/bin/switch-to-source-kernel"
}

create_kernel_management_helper() {
  echo "Creating kernel management helper script..."
  
  # Ensure target directory exists before creating the helper script
  mkdir -p "${MNT}/usr/local/bin"
  # Create helper script for managing kernel versions
  cat > "${MNT}/usr/local/bin/manage-kernels" <<'EOF'
#!/bin/bash
# Helper script to manage kernel versions and backups

if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root" 
   exit 1
fi

show_help() {
    cat <<'HELP'
Usage: manage-kernels <command>

Commands:
  list      - Show all installed kernel versions
  preserve  - Add current kernels to preservation set
  clean     - Interactively remove old kernel versions
  info      - Show detailed kernel information

Examples:
  manage-kernels list        # List all kernels
  manage-kernels preserve    # Preserve current kernels
  manage-kernels clean       # Clean old kernels
HELP
}

list_kernels() {
    echo "================================================================================"
    echo "Installed Kernel Packages"
    echo "================================================================================"
    
    # Try multiple methods to list kernels
    if command -v qlist &>/dev/null; then
        echo "Binary kernels:"
        qlist -ICv sys-kernel/gentoo-kernel-bin 2>/dev/null || echo "  None"
        echo
        echo "Source kernels:"
        qlist -ICv sys-kernel/gentoo-kernel 2>/dev/null || echo "  None"
    elif command -v eix &>/dev/null; then
        eix -I sys-kernel/gentoo-kernel-bin sys-kernel/gentoo-kernel
    else
        emerge -s sys-kernel/gentoo-kernel | grep -E "^\*|Installed versions"
    fi
    
    echo
    echo "================================================================================"
    echo "Available Kernel Sources"
    echo "================================================================================"
    eselect kernel list
    
    echo
    echo "================================================================================"
    echo "Preserved Kernels (in /etc/portage/sets/kernels)"
    echo "================================================================================"
    if [[ -f /etc/portage/sets/kernels ]]; then
        grep -v '^#' /etc/portage/sets/kernels | grep -v '^$' || echo "  None explicitly preserved"
    else
        echo "  Preservation set not found"
    fi
    
    echo
    echo "================================================================================"
    echo "Boot Entries (in /boot)"
    echo "================================================================================"
    ls -lh /boot/vmlinuz-* 2>/dev/null || echo "  No kernels found in /boot"
}

preserve_current() {
    echo "================================================================================"
    echo "Preserve Current Kernels"
    echo "================================================================================"
    echo
    
    mkdir -p /etc/portage/sets
    
    # Get all installed kernel packages
    if command -v qlist &>/dev/null; then
        KERNELS=$(qlist -ICv sys-kernel/gentoo-kernel-bin sys-kernel/gentoo-kernel 2>/dev/null || true)
    elif command -v eix &>/dev/null; then
        # Fallback: use eix to list installed kernel package names
        KERNELS=$(eix -I --only-names sys-kernel/gentoo-kernel-bin sys-kernel/gentoo-kernel 2>/dev/null || true)
    else
        echo "Error: Unable to determine installed kernels to preserve."
        echo "Neither 'qlist' (from portage-utils) nor 'eix' is available."
        echo "Please install 'portage-utils' (emerge portage-utils) or 'eix' and retry."
        exit 1
    fi
    
    if [[ -z "${KERNELS}" ]]; then
        echo "No kernels found to preserve."
        exit 0
    fi
    
    echo "Current kernels:"
    echo "${KERNELS}"
    echo
    read -r -p "Add these to preservation set? (y/n): " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo "Cancelled."
        exit 0
    fi
    
    # Avoid duplicating the preserved-kernels comment if it already exists.
    if ! grep -q '^# Preserved on' /etc/portage/sets/kernels 2>/dev/null; then
        echo "# Preserved on $(date)" >> /etc/portage/sets/kernels
    fi

    echo "${KERNELS}" | while read -r pkg; do
        if [[ -n "${pkg}" ]]; then
            # Only append the package if it is not already present as a full line.
            if ! grep -Fxq "${pkg}" /etc/portage/sets/kernels 2>/dev/null; then
                echo "${pkg}" >> /etc/portage/sets/kernels
                echo "  Preserved: ${pkg}"
            else
                echo "  Already preserved: ${pkg}"
            fi
        fi
    done <<< "${KERNELS}"
    
    echo
    echo "Kernels added to /etc/portage/sets/kernels"
}

clean_old_kernels() {
    echo "================================================================================"
    echo "Clean Old Kernel Versions"
    echo "================================================================================"
    echo
    echo "WARNING: This will help you remove old kernel versions."
    echo "         Always keep at least 2 kernel versions for fallback!"
    echo
    
    list_kernels
    
    echo
    echo "================================================================================"
    echo
    read -r -p "Do you want to clean old kernels? (yes/no): " confirm
    if [[ "${confirm}" != "yes" ]]; then
        echo "Cancelled."
        exit 0
    fi
    
    echo
    echo "Use 'emerge --deselect' to remove kernels from world, then 'emerge --depclean'"
    echo "Example: emerge --deselect sys-kernel/gentoo-kernel-bin:6.12.58"
    echo
    read -r -p "Run interactive depclean now? (y/n): " run_clean
    if [[ "${run_clean}" == "y" || "${run_clean}" == "Y" ]]; then
        emerge --depclean --ask
    fi
}

show_info() {
    echo "================================================================================"
    echo "Kernel System Information"
    echo "================================================================================"
    echo
    echo "Current running kernel:"
    uname -r
    echo
    echo "Currently selected kernel source:"
    eselect kernel show
    echo
    
    list_kernels
}

case "${1:-}" in
    list)
        list_kernels
        ;;
    preserve)
        preserve_current
        ;;
    clean)
        clean_old_kernels
        ;;
    info)
        show_info
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        echo "ERROR: Unknown command: $1"
        echo
        show_help
        exit 1
        ;;
esac
EOF

  chmod +x "${MNT}/usr/local/bin/manage-kernels"
  
  echo "Kernel management helper created at /usr/local/bin/manage-kernels"
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
  install_kde_plasma
  install_blender
  install_rocm
  install_comfyui_and_sdxl
  install_zfs_and_create_pool
  setup_snapshot_management
  setup_ml_boot_selector
  configure_nvme_optimizations
  create_kernel_switch_helper
  create_kernel_management_helper
  finalize_users_passwords

  echo
  echo "============================================================"
  echo "Install complete."
  echo "Next steps:"
  echo "  1) Exit chroot (if you entered manually), then:"
  echo "  2) umount -R ${MNT}"
  echo "  3) reboot"
  echo
  echo "After reboot:"
  echo "  - ZFS datasets mounted under: ${ZFS_MNT_BASE}"
  echo "  - Run 'setup-comfyui' to install ComfyUI and download SDXL models"
  echo "  - Use 'manage-snapshots create' to create system snapshots"
  echo "  - Blender Cycles configured for AMD Radeon 780M iGPU"
  echo "  - ROCm enabled for GPU compute (if installed)"
  if [[ "${USE_BINARY_KERNEL}" == "yes" ]] || [[ "${INSTALL_DUAL_KERNEL:-no}" == "yes" ]]; then
    echo
    echo "Kernel management:"
    echo "  - Binary kernel installed for fast initial setup"
    echo "  - Old kernel versions can be preserved for fallback (run 'sudo manage-kernels preserve')"
    echo "  - To switch to source kernel for optimization:"
    echo "    sudo switch-to-source-kernel"
    echo "  - To manage kernel versions:"
    echo "    sudo manage-kernels list"
  fi
  echo "============================================================"
}

# Globals set during partitioning
OS_ESP=""
OS_ROOT=""
DATA_PART=""

main "$@"

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

# Phase 0 wrappers around existing monolithic functions.
# Behavior is intentionally unchanged; this file only introduces
# module-shaped entrypoints for later extraction.

module_preflight() {
  require_root
  require_uefi

  init_logging
  enable_debug_trace

  log_with_elapsed "gentoo-um890pro-installer version: ${VERSION}"
  log_with_elapsed "Installation started"

  for c in lsblk blkid awk sed; do
    need_cmd "$c" || { echo "ERROR: missing required command: $c"; exit 1; }
  done
}

module_disks_prepare() {
  confirm_disks
  stop_mounts
}

module_disks_partition_and_mount() {
  partition_disks
  format_os
  mount_btrfs_layout
  fetch_stage3_and_prep
}

module_base_system() { install_base_system; }
module_kernel() { install_kernel; }
module_boot() { configure_fstab_bootloader; }
module_services() { enable_network_and_services; }
module_desktop() { install_kde_plasma; }
module_ai_blender() { install_blender; }
module_ai_rocm() { install_rocm; }
module_ai_comfyui() { install_comfyui_and_sdxl; }
module_data_pool() { install_zfs_and_create_pool; }
module_snapshots() { setup_snapshot_management; }
module_ml_boot_selector() { setup_ml_boot_selector; }
module_nvme_optimizations() { configure_nvme_optimizations; }
module_kernel_switch_helper() { create_kernel_switch_helper; }
module_kernel_management_helper() { create_kernel_management_helper; }
module_finalize_users() { finalize_users_passwords; }

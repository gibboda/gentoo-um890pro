#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

run_phase0_pipeline() {
  module_preflight
  module_disks_prepare
  module_disks_partition_and_mount
  module_base_system
  module_kernel
  module_boot
  module_services
  module_desktop
  module_ai_blender
  module_ai_rocm
  module_ai_comfyui
  module_data_pool
  module_snapshots
  module_ml_boot_selector
  module_nvme_optimizations
  module_kernel_switch_helper
  module_kernel_management_helper
  module_finalize_users
}

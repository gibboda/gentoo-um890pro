#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

# Ordered map of phase id -> module function
PHASE_IDS=(
  preflight
  disks-prepare
  disks-partition-and-mount
  base-system
  kernel
  boot
  services
  desktop
  ai-blender
  ai-rocm
  ai-comfyui
  data-pool
  snapshots
  ml-boot-selector
  nvme-optimizations
  kernel-switch-helper
  kernel-management-helper
  finalize-users
)

phase_func_for() {
  local phase="${1:?phase is required}"
  case "${phase}" in
    preflight) echo "module_preflight" ;;
    disks-prepare) echo "module_disks_prepare" ;;
    disks-partition-and-mount) echo "module_disks_partition_and_mount" ;;
    base-system) echo "module_base_system" ;;
    kernel) echo "module_kernel" ;;
    boot) echo "module_boot" ;;
    services) echo "module_services" ;;
    desktop) echo "module_desktop" ;;
    ai-blender) echo "module_ai_blender" ;;
    ai-rocm) echo "module_ai_rocm" ;;
    ai-comfyui) echo "module_ai_comfyui" ;;
    data-pool) echo "module_data_pool" ;;
    snapshots) echo "module_snapshots" ;;
    ml-boot-selector) echo "module_ml_boot_selector" ;;
    nvme-optimizations) echo "module_nvme_optimizations" ;;
    kernel-switch-helper) echo "module_kernel_switch_helper" ;;
    kernel-management-helper) echo "module_kernel_management_helper" ;;
    finalize-users) echo "module_finalize_users" ;;
    *)
      echo "ERROR: no module function mapping for phase '${phase}'" >&2
      return 1
      ;;
  esac
}

resolve_phase_plan() {
  RESOLVED_PHASES=(
    preflight
    disks-prepare
    disks-partition-and-mount
    base-system
    kernel
    boot
    services
  )

  if [[ "${INSTALL_KDE_PLASMA:-no}" == "yes" ]]; then
    RESOLVED_PHASES+=(desktop)
  fi
  if [[ "${INSTALL_BLENDER:-no}" == "yes" ]]; then
    RESOLVED_PHASES+=(ai-blender)
  fi
  if [[ "${INSTALL_ROCM:-no}" == "yes" ]]; then
    RESOLVED_PHASES+=(ai-rocm)
  fi
  if [[ "${INSTALL_COMFYUI:-no}" == "yes" ]]; then
    RESOLVED_PHASES+=(ai-comfyui)
  fi

  RESOLVED_PHASES+=(
    data-pool
    snapshots
    ml-boot-selector
    nvme-optimizations
    kernel-switch-helper
    kernel-management-helper
    finalize-users
  )
}

print_resolved_phase_plan() {
  local phase
  echo "Resolved phase plan (${#RESOLVED_PHASES[@]} phases):"
  for phase in "${RESOLVED_PHASES[@]}"; do
    echo "  - ${phase}"
  done
}

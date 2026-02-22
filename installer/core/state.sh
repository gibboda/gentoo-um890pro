#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

STATE_ROOT_DEFAULT="/var/lib/um890-installer/state"
STATE_DIR="${STATE_DIR:-${STATE_ROOT_DEFAULT}}"

state_dir_init() {
  mkdir -p "${STATE_DIR}"
}

checkpoint_done() {
  local phase="${1:?phase is required}"
  [[ -f "${STATE_DIR}/${phase}.done" ]]
}

checkpoint_mark() {
  local phase="${1:?phase is required}"
  : > "${STATE_DIR}/${phase}.done"
}

checkpoint_clear_from() {
  local start_phase="${1:?phase is required}"
  local started="no"
  local phase=""

  for phase in "${RESOLVED_PHASES[@]}"; do
    if [[ "${phase}" == "${start_phase}" ]]; then
      started="yes"
    fi
    [[ "${started}" == "yes" ]] || continue
    rm -f "${STATE_DIR}/${phase}.done"
  done

  if [[ "${started}" != "yes" ]]; then
    echo "ERROR: unknown phase for --force-from: ${start_phase}" >&2
    return 1
  fi
}

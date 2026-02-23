#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

FORCE_FROM_PHASE="${FORCE_FROM_PHASE:-}"

run_phase_pipeline() {
  local phase=""
  local func=""

  if [[ "${RESOLVED_PHASES[*]+set}" != "set" ]] || [[ "${#RESOLVED_PHASES[@]}" -eq 0 ]]; then
    echo "ERROR: RESOLVED_PHASES is unset or empty; call resolve_phase_plan first" >&2
    return 1
  fi

  state_dir_init

  if [[ -n "${FORCE_FROM_PHASE}" ]]; then
    echo "Force rerun requested from phase: ${FORCE_FROM_PHASE}"
    checkpoint_clear_from "${FORCE_FROM_PHASE}"
  fi

  for phase in "${RESOLVED_PHASES[@]}"; do
    if [[ "${phase}" != "preflight" ]] && checkpoint_done "${phase}"; then
      echo "[SKIP] ${phase} (checkpoint exists)"
      continue
    fi

    func="$(phase_func_for "${phase}")"
    if ! declare -F "${func}" >/dev/null 2>&1; then
      echo "ERROR: phase '${phase}' mapped to missing function '${func}'" >&2
      return 1
    fi

    echo "[RUN ] ${phase} -> ${func}"
    "${func}"
    checkpoint_mark "${phase}"
  done
}

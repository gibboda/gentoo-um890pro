#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALLER="${REPO_ROOT}/src/gentoo-um890pro-install.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "${expected}" != "${actual}" ]]; then
    fail "${message}: expected '${expected}', got '${actual}'"
  fi
}

source_installer() {
  # Save any existing ERR trap so we can restore it after sourcing the installer.
  local previous_err_trap
  previous_err_trap="$(trap -p ERR || true)"

  # Source the installer without executing main(), matching by pattern rather
  # than unconditionally deleting the last line.
  # shellcheck disable=SC1090
  source <(sed '/^[[:space:]]*main "\$@"/d' "${INSTALLER}")

  # The installer installs its own ERR trap; restore the original trap (if any)
  # so that the test harness retains control over failure handling.
  if [[ -n "${previous_err_trap}" ]]; then
    eval "${previous_err_trap}"
  else
    trap - ERR
  fi
}

run_profile_case() {
  local requested_profile="$1"
  local expected_profile="$2"
  local expected_dual_kernel="$3"
  local expected_kde="$4"
  local expected_rocm="$5"
  local expected_comfyui="$6"
  local expected_blender="$7"

  INSTALL_PROFILE="${requested_profile}"
  resolve_profile >/dev/null

  assert_eq "${expected_profile}" "${INSTALL_PROFILE}" "resolved profile mismatch for ${requested_profile}"
  assert_eq "${expected_dual_kernel}" "${INSTALL_DUAL_KERNEL}" "dual-kernel toggle mismatch for ${requested_profile}"
  assert_eq "${expected_kde}" "${INSTALL_KDE_PLASMA}" "KDE toggle mismatch for ${requested_profile}"
  assert_eq "${expected_rocm}" "${INSTALL_ROCM}" "ROCm toggle mismatch for ${requested_profile}"
  assert_eq "${expected_comfyui}" "${INSTALL_COMFYUI}" "ComfyUI toggle mismatch for ${requested_profile}"
  assert_eq "${expected_blender}" "${INSTALL_BLENDER}" "Blender toggle mismatch for ${requested_profile}"
}

assert_default_profile() {
  local default_profile
  # shellcheck disable=SC2016  # ${INSTALL_PROFILE:-...} is a literal sed pattern, not a shell expansion
  default_profile="$(sed -n 's/^INSTALL_PROFILE="\${INSTALL_PROFILE:-\(.*\)}"$/\1/p' "${INSTALLER}")"
  assert_eq "core-openrc-dualkernel" "${default_profile}" "default INSTALL_PROFILE should be core-openrc-dualkernel"
}

assert_invalid_profile_error() {
  local output

  set +e
  output="$(
    BASH_ENV=/dev/null bash --noprofile --norc -c '
      set -euo pipefail
      source <(sed '"'"'/^[[:space:]]*main "\$@"/d'"'"' "'"${INSTALLER}"'")
      INSTALL_PROFILE="not-a-real-profile"
      resolve_profile
    ' 2>&1
  )"
  local status=$?
  set -e

  if [[ ${status} -eq 0 ]]; then
    fail "invalid profile unexpectedly succeeded"
  fi

  [[ "${output}" == *"ERROR: unsupported INSTALL_PROFILE value: 'not-a-real-profile'"* ]] \
    || fail "invalid profile error message missing unsupported-value text"
  [[ "${output}" == *"core-openrc-dualkernel (core)"* ]] \
    || fail "invalid profile error message missing core acceptable value"
  [[ "${output}" == *"desktop-openrc-dualkernel-kde (desktop)"* ]] \
    || fail "invalid profile error message missing desktop acceptable value"
  [[ "${output}" == *"full-openrc-dualkernel-kde-ai (full-ai)"* ]] \
    || fail "invalid profile error message missing full-ai acceptable value"
}

main() {
  source_installer

  assert_default_profile

  run_profile_case "core-openrc-dualkernel" "core-openrc-dualkernel" "yes" "no" "no" "no" "no"
  run_profile_case "desktop-openrc-dualkernel-kde" "desktop-openrc-dualkernel-kde" "yes" "yes" "no" "no" "no"
  run_profile_case "full-openrc-dualkernel-kde-ai" "full-openrc-dualkernel-kde-ai" "yes" "yes" "yes" "yes" "yes"

  run_profile_case "core" "core-openrc-dualkernel" "yes" "no" "no" "no" "no"
  run_profile_case "desktop" "desktop-openrc-dualkernel-kde" "yes" "yes" "no" "no" "no"
  run_profile_case "full-ai" "full-openrc-dualkernel-kde-ai" "yes" "yes" "yes" "yes" "yes"

  assert_invalid_profile_error

  echo "All install profile resolution tests passed!"
}

main "$@"

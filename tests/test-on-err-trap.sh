#!/usr/bin/env bash
# Regression coverage for the installer on_err ERR trap.
# Sources the installer without executing main(), matching
# tests/test-install-profile-resolution.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALLER="${REPO_ROOT}/src/gentoo-um890pro-install.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Run a snippet in a subprocess that has sourced the installer (no main).
# Prints combined stdout/stderr to stdout; caller inspects $?.
run_installer_snippet() {
  local snippet="$1"

  BASH_ENV=/dev/null bash --noprofile --norc -c '
    set -euo pipefail
    source <(sed "/^[[:space:]]*main \"\$@\"/d" "$0")
    LOG_ENABLED=no
    eval "$1"
  ' "${INSTALLER}" "${snippet}" 2>&1
}

assert_fatal_false() {
  local output=""
  local status=0

  set +e
  output="$(run_installer_snippet $'false\necho SHOULD_NOT_REACH')"
  status=$?
  set -e

  if [[ ${status} -eq 0 ]]; then
    fail "fatal false unexpectedly succeeded (exit=0). output:${output:+$'\n'}${output}"
  fi
  if [[ "${output}" == *"SHOULD_NOT_REACH"* ]]; then
    fail "fatal false continued after the failed command. output:${output:+$'\n'}${output}"
  fi
  if ! grep -Eq 'ERROR: command failed \(exit=1\) at .+:[0-9]+: false' <<<"${output}"; then
    fail "fatal false missing command/source/line/exit context. output:${output:+$'\n'}${output}"
  fi
}

assert_best_effort_false_continues() {
  local output=""
  local status=0

  set +e
  output="$(run_installer_snippet $'set +e\nfalse\nprintf "%s\\n" CONTINUED')"
  status=$?
  set -e

  if [[ ${status} -ne 0 ]]; then
    fail "best-effort false aborted the script (exit=${status}). output:${output:+$'\n'}${output}"
  fi
  if [[ "${output}" != *"CONTINUED"* ]]; then
    fail "best-effort false did not continue. output:${output:+$'\n'}${output}"
  fi
  if [[ "${output}" == *"ERROR: command failed"* ]]; then
    fail "best-effort false was treated as fatal. output:${output:+$'\n'}${output}"
  fi
}

assert_fatal_after_best_effort() {
  local output=""
  local status=0

  set +e
  output="$(run_installer_snippet $'set +e\nfalse\nprintf "%s\\n" AFTER_BEST_EFFORT\nset -e\nfalse\necho SHOULD_NOT_REACH')"
  status=$?
  set -e

  if [[ ${status} -eq 0 ]]; then
    fail "fatal false after best-effort unexpectedly succeeded. output:${output:+$'\n'}${output}"
  fi
  if [[ "${output}" != *"AFTER_BEST_EFFORT"* ]]; then
    fail "best-effort region did not continue before the later fatal failure. output:${output:+$'\n'}${output}"
  fi
  if [[ "${output}" == *"SHOULD_NOT_REACH"* ]]; then
    fail "later fatal false continued after the failed command. output:${output:+$'\n'}${output}"
  fi
  if ! grep -Eq 'ERROR: command failed \(exit=1\) at .+:[0-9]+: false' <<<"${output}"; then
    fail "later fatal false missing error context (trap may not have been restored). output:${output:+$'\n'}${output}"
  fi
}

assert_fatal_log_context() {
  local output=""
  local status=0
  local log_file

  log_file="$(mktemp)"
  printf 'log-sentinel-on-err\n' > "${log_file}"

  set +e
  output="$(
    LOG_FILE="${log_file}" BASH_ENV=/dev/null bash --noprofile --norc -c '
      set -euo pipefail
      source <(sed "/^[[:space:]]*main \"\$@\"/d" "$0")
      LOG_ENABLED=yes
      LOG_FILE="$1"
      false
      echo SHOULD_NOT_REACH
    ' "${INSTALLER}" "${log_file}" 2>&1
  )"
  status=$?
  set -e
  rm -f "${log_file}"

  if [[ ${status} -eq 0 ]]; then
    fail "logged fatal false unexpectedly succeeded. output:${output:+$'\n'}${output}"
  fi
  if [[ "${output}" != *"ERROR: log file: ${log_file}"* ]]; then
    fail "logged fatal false missing log file path. output:${output:+$'\n'}${output}"
  fi
  if [[ "${output}" != *"log-sentinel-on-err"* ]]; then
    fail "logged fatal false missing log tail. output:${output:+$'\n'}${output}"
  fi
}

main() {
  [[ -f "${INSTALLER}" ]] || fail "installer not found: ${INSTALLER}"

  assert_fatal_false
  assert_best_effort_false_continues
  assert_fatal_after_best_effort
  assert_fatal_log_context

  echo "All on_err trap tests passed!"
}

main "$@"

#!/usr/bin/env bash
set -euo pipefail

# Test script for bump-version.sh auto mode
# Creates temporary git repos and verifies auto mode behavior

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUMP_SCRIPT="$ROOT_DIR/scripts/bump-version.sh"

TEST_FAILED=0
TEST_PASSED=0

# Set to 1 to preserve test directories on failure for debugging
PRESERVE_TEST_DIRS="${PRESERVE_TEST_DIRS:-0}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_test() {
  echo -e "${YELLOW}[TEST]${NC} $*"
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
  ((TEST_PASSED++)) || true
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*"
  ((TEST_FAILED++)) || true
}

# Create a temporary test repository
create_test_repo() {
  local test_dir="$1"
  
  mkdir -p "$test_dir"
  cd "$test_dir"
  
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"
  
  # Create initial files
  echo "1.0.0" > VERSION
  mkdir -p src docs
  cat > src/gentoo-um890pro-install.sh << 'EOF'
#!/usr/bin/env bash
VERSION="1.0.0"
echo "Installer version $VERSION"
EOF
  chmod +x src/gentoo-um890pro-install.sh
  
  cat > docs/CHANGELOG.md << 'EOF'
# Changelog

## [Unreleased]

EOF
  
  git add .
  git commit -q -m "chore: initial commit"
  git tag -a "v1.0.0" -m "Initial release"
}

# Verify version in all files
verify_version() {
  local expected_version="$1"
  local test_dir="$2"
  
  cd "$test_dir"
  
  local version_file
  local installer_version
  version_file=$(tr -d '\r\n' < VERSION)
  installer_version=$(grep '^VERSION=' src/gentoo-um890pro-install.sh | head -1 | sed 's/VERSION="\([^"]*\)"/\1/')
  
  if [[ "$version_file" != "$expected_version" ]]; then
    log_fail "VERSION file has $version_file, expected $expected_version"
    return 1
  fi
  
  if [[ "$installer_version" != "$expected_version" ]]; then
    log_fail "Installer has $installer_version, expected $expected_version"
    return 1
  fi
  
  return 0
}

# Verify CHANGELOG.md structure
verify_changelog() {
  local expected_version="$1"
  local test_dir="$2"
  
  cd "$test_dir"
  
  if ! grep -q "## \[${expected_version}\]" docs/CHANGELOG.md; then
    log_fail "docs/CHANGELOG.md missing version ${expected_version}"
    return 1
  fi
  
  return 0
}

# Helper function to run test and cleanup
run_test() {
  local test_name="$1"
  local test_dir="$2"
  local expected_version="$3"
  local allow_dirty_arg="${4:-false}"
  
  # Run auto mode on a clean repository (no --allow-dirty needed for tests since
  # all changes are committed before running the script)
  local bump_output
  if [[ "$allow_dirty_arg" == "true" ]]; then
    if ! bump_output=$(bash scripts/bump-version.sh auto --allow-dirty 2>&1); then
      log_fail "$test_name: bump-version.sh exited with non-zero status"
      echo "$bump_output"
      if [[ "$PRESERVE_TEST_DIRS" == "1" ]]; then
        echo "Test directory preserved at: $test_dir"
      else
        rm -rf "$test_dir"
      fi
      return 1
    fi
  elif ! bump_output=$(bash scripts/bump-version.sh auto 2>&1); then
    log_fail "$test_name: bump-version.sh exited with non-zero status"
    echo "$bump_output"
    if [[ "$PRESERVE_TEST_DIRS" == "1" ]]; then
      echo "Test directory preserved at: $test_dir"
    else
      rm -rf "$test_dir"
    fi
    return 1
  fi
  
  if verify_version "$expected_version" "$test_dir" && verify_changelog "$expected_version" "$test_dir"; then
    log_pass "$test_name: correctly bumped to v${expected_version}"
    rm -rf "$test_dir"
    return 0
  else
    log_fail "$test_name: Failed"
    echo "Bump output: $bump_output"
    if [[ "$PRESERVE_TEST_DIRS" == "1" ]]; then
      echo "Test directory preserved at: $test_dir"
    else
      rm -rf "$test_dir"
    fi
    return 1
  fi
}

# Test A: 1 fix commit -> v1.0.1 (patch bump)
test_a() {
  log_test "Test A: 1 fix commit -> v1.0.1"
  
  local test_dir
  test_dir=$(mktemp -d)
  create_test_repo "$test_dir"
  
  cd "$test_dir"
  echo "fix 1" >> file1.txt
  git add file1.txt
  git commit -q -m "fix: fixed issue #1"
  
  # Copy bump script
  mkdir -p scripts
  cp "$BUMP_SCRIPT" scripts/
  
  run_test "Test A" "$test_dir" "1.0.1"
}

# Test B: 2 fix commits -> v1.1.0 (minor bump)
test_b() {
  log_test "Test B: 2 fix commits -> v1.1.0"
  
  local test_dir
  test_dir=$(mktemp -d)
  create_test_repo "$test_dir"
  
  cd "$test_dir"
  echo "fix 1" >> file1.txt
  git add file1.txt
  git commit -q -m "fix: fixed issue #1"
  
  echo "fix 2" >> file2.txt
  git add file2.txt
  git commit -q -m "fix: fixed issue #2"
  
  # Copy bump script
  mkdir -p scripts
  cp "$BUMP_SCRIPT" scripts/
  
  run_test "Test B" "$test_dir" "1.1.0"
}

# Test C: 7 fix commits -> v2.0.0 (major bump)
test_c() {
  log_test "Test C: 7 fix commits -> v2.0.0"
  
  local test_dir
  test_dir=$(mktemp -d)
  create_test_repo "$test_dir"
  
  cd "$test_dir"
  for i in {1..7}; do
    echo "fix $i" >> "file${i}.txt"
    git add "file${i}.txt"
    git commit -q -m "fix: fixed issue #${i}"
  done
  
  # Copy bump script
  mkdir -p scripts
  cp "$BUMP_SCRIPT" scripts/
  
  run_test "Test C" "$test_dir" "2.0.0"
}

# Test D: 1 perf commit -> v2.0.0 (major trigger)
test_d() {
  log_test "Test D: 1 perf commit -> v2.0.0"
  
  local test_dir
  test_dir=$(mktemp -d)
  create_test_repo "$test_dir"
  
  cd "$test_dir"
  echo "perf improvement" >> file1.txt
  git add file1.txt
  git commit -q -m "perf: optimized database queries"
  
  # Copy bump script
  mkdir -p scripts
  cp "$BUMP_SCRIPT" scripts/
  
  run_test "Test D" "$test_dir" "2.0.0"
}

# Test E: docs-only commits -> v1.0.1 (patch bump, no fix/update/major triggers)
test_e() {
  log_test "Test E: docs-only commits -> v1.0.1"
  
  local test_dir
  test_dir=$(mktemp -d)
  create_test_repo "$test_dir"
  
  cd "$test_dir"
  echo "docs update" >> README.md
  git add README.md
  git commit -q -m "docs: updated documentation"
  
  echo "more docs" >> README.md
  git add README.md
  git commit -q -m "docs: added examples"
  
  # Copy bump script
  mkdir -p scripts
  cp "$BUMP_SCRIPT" scripts/
  
  run_test "Test E" "$test_dir" "1.0.1"
}

# Test F: Breaking change marker (!) -> v2.0.0
test_f() {
  log_test "Test F: Breaking change marker (!) -> v2.0.0"
  
  local test_dir
  test_dir=$(mktemp -d)
  create_test_repo "$test_dir"
  
  cd "$test_dir"
  echo "breaking change" >> file1.txt
  git add file1.txt
  git commit -q -m "fix!: changed API signature"
  
  # Copy bump script
  mkdir -p scripts
  cp "$BUMP_SCRIPT" scripts/
  
  run_test "Test F" "$test_dir" "2.0.0"
}

# Test G: feat commit -> v2.0.0 (major trigger)
test_g() {
  log_test "Test G: feat commit -> v2.0.0"
  
  local test_dir
  test_dir=$(mktemp -d)
  create_test_repo "$test_dir"
  
  cd "$test_dir"
  echo "new feature" >> file1.txt
  git add file1.txt
  git commit -q -m "feat: added new API endpoint"
  
  # Copy bump script
  mkdir -p scripts
  cp "$BUMP_SCRIPT" scripts/
  
  run_test "Test G" "$test_dir" "2.0.0"
}

# Test H: BREAKING CHANGE in body -> v2.0.0
test_h() {
  log_test "Test H: BREAKING CHANGE in body -> v2.0.0"
  
  local test_dir
  test_dir=$(mktemp -d)
  create_test_repo "$test_dir"
  
  cd "$test_dir"
  echo "breaking change body" >> file1.txt
  git add file1.txt
  git commit -q -m "feat: adjust configuration" -m "BREAKING CHANGE: removed legacy flag"
  
  # Copy bump script
  mkdir -p scripts
  cp "$BUMP_SCRIPT" scripts/
  
  run_test "Test H" "$test_dir" "2.0.0"
}

# Test I: refactor commit -> v2.0.0 (major trigger)
test_i() {
  log_test "Test I: refactor commit -> v2.0.0"
  
  local test_dir
  test_dir=$(mktemp -d)
  create_test_repo "$test_dir"
  
  cd "$test_dir"
  echo "refactor" >> file1.txt
  git add file1.txt
  git commit -q -m "refactor: rewrote authentication system"
  
  # Copy bump script
  mkdir -p scripts
  cp "$BUMP_SCRIPT" scripts/
  
  run_test "Test I" "$test_dir" "2.0.0"
}

# Test J: update type commit -> counted as fix
test_j() {
  log_test "Test J: 2 update commits -> v1.1.0"
  
  local test_dir
  test_dir=$(mktemp -d)
  create_test_repo "$test_dir"
  
  cd "$test_dir"
  echo "update 1" >> file1.txt
  git add file1.txt
  git commit -q -m "update: updated dependency versions"
  
  echo "update 2" >> file2.txt
  git add file2.txt
  git commit -q -m "update: updated configuration"
  
  # Copy bump script
  mkdir -p scripts
  cp "$BUMP_SCRIPT" scripts/
  
  run_test "Test J" "$test_dir" "1.1.0"
}

# Test K: --allow-dirty accepted after positional command
test_k() {
  log_test "Test K: auto --allow-dirty works with dirty repository"

  local test_dir
  test_dir=$(mktemp -d)
  create_test_repo "$test_dir"

  cd "$test_dir"
  echo "fix 1" >> file1.txt
  git add file1.txt
  git commit -q -m "fix: fixed issue #1"

  # Leave the repository dirty to verify --allow-dirty handling
  echo "uncommitted change" >> dirty.txt

  # Copy bump script
  mkdir -p scripts
  cp "$BUMP_SCRIPT" scripts/

  run_test "Test K" "$test_dir" "1.0.1" true
}

# Run all tests
echo "=========================================="
echo "Testing bump-version.sh auto mode"
echo "=========================================="
echo ""

test_a
test_b
test_c
test_d
test_e
test_f
test_g
test_h
test_i
test_j
test_k

echo ""
echo "=========================================="
echo "Test Results"
echo "=========================================="
echo -e "${GREEN}Passed: ${TEST_PASSED}${NC}"
echo -e "${RED}Failed: ${TEST_FAILED}${NC}"
echo ""

if [[ $TEST_FAILED -eq 0 ]]; then
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}Some tests failed!${NC}"
  exit 1
fi

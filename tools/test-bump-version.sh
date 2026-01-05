#!/usr/bin/env bash
set -euo pipefail

# Test script for bump-version.sh auto mode
# Creates temporary git repos and verifies auto mode behavior

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUMP_SCRIPT="$ROOT_DIR/scripts/bump-version.sh"

TEST_FAILED=0
TEST_PASSED=0

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
  cat > gentoo-um890pro-install.sh << 'EOF'
#!/usr/bin/env bash
VERSION="1.0.0"
echo "Installer version $VERSION"
EOF
  chmod +x gentoo-um890pro-install.sh
  
  cat > CHANGELOG.md << 'EOF'
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
  
  local version_file=$(tr -d '\r\n' < VERSION)
  local installer_version=$(grep '^VERSION=' gentoo-um890pro-install.sh | head -1 | sed 's/VERSION="\([^"]*\)"/\1/')
  
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
  
  if ! grep -q "## \[${expected_version}\]" CHANGELOG.md; then
    log_fail "CHANGELOG.md missing version ${expected_version}"
    return 1
  fi
  
  return 0
}

# Test A: 1 fix commit -> v1.0.1 (patch bump)
test_a() {
  log_test "Test A: 1 fix commit -> v1.0.1"
  
  local test_dir=$(mktemp -d)
  create_test_repo "$test_dir"
  
  cd "$test_dir"
  echo "fix 1" >> file1.txt
  git add file1.txt
  git commit -q -m "fix: fixed issue #1"
  
  # Copy bump script
  mkdir -p scripts
  cp "$BUMP_SCRIPT" scripts/
  
  # Run auto mode
  bash scripts/bump-version.sh auto --allow-dirty >/dev/null 2>&1
  
  if verify_version "1.0.1" "$test_dir" && verify_changelog "1.0.1" "$test_dir"; then
    log_pass "Test A: 1 fix commit correctly bumped to v1.0.1"
  else
    log_fail "Test A: Failed"
  fi
  
  rm -rf "$test_dir"
}

# Test B: 2 fix commits -> v1.1.0 (minor bump)
test_b() {
  log_test "Test B: 2 fix commits -> v1.1.0"
  
  local test_dir=$(mktemp -d)
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
  
  # Run auto mode
  bash scripts/bump-version.sh auto --allow-dirty >/dev/null 2>&1
  
  if verify_version "1.1.0" "$test_dir" && verify_changelog "1.1.0" "$test_dir"; then
    log_pass "Test B: 2 fix commits correctly bumped to v1.1.0"
  else
    log_fail "Test B: Failed"
  fi
  
  rm -rf "$test_dir"
}

# Test C: 7 fix commits -> v2.0.0 (major bump)
test_c() {
  log_test "Test C: 7 fix commits -> v2.0.0"
  
  local test_dir=$(mktemp -d)
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
  
  # Run auto mode
  bash scripts/bump-version.sh auto --allow-dirty >/dev/null 2>&1
  
  if verify_version "2.0.0" "$test_dir" && verify_changelog "2.0.0" "$test_dir"; then
    log_pass "Test C: 7 fix commits correctly bumped to v2.0.0"
  else
    log_fail "Test C: Failed"
  fi
  
  rm -rf "$test_dir"
}

# Test D: 1 perf commit -> v2.0.0 (major trigger)
test_d() {
  log_test "Test D: 1 perf commit -> v2.0.0"
  
  local test_dir=$(mktemp -d)
  create_test_repo "$test_dir"
  
  cd "$test_dir"
  echo "perf improvement" >> file1.txt
  git add file1.txt
  git commit -q -m "perf: optimized database queries"
  
  # Copy bump script
  mkdir -p scripts
  cp "$BUMP_SCRIPT" scripts/
  
  # Run auto mode
  bash scripts/bump-version.sh auto --allow-dirty >/dev/null 2>&1
  
  if verify_version "2.0.0" "$test_dir" && verify_changelog "2.0.0" "$test_dir"; then
    log_pass "Test D: 1 perf commit correctly bumped to v2.0.0"
  else
    log_fail "Test D: Failed"
  fi
  
  rm -rf "$test_dir"
}

# Test E: docs-only commits -> v1.0.1 (patch bump, no fix/update/major triggers)
test_e() {
  log_test "Test E: docs-only commits -> v1.0.1"
  
  local test_dir=$(mktemp -d)
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
  
  # Run auto mode
  bash scripts/bump-version.sh auto --allow-dirty >/dev/null 2>&1
  
  if verify_version "1.0.1" "$test_dir" && verify_changelog "1.0.1" "$test_dir"; then
    log_pass "Test E: docs-only commits correctly bumped to v1.0.1"
  else
    log_fail "Test E: Failed"
  fi
  
  rm -rf "$test_dir"
}

# Test F: Breaking change marker (!) -> v2.0.0
test_f() {
  log_test "Test F: Breaking change marker (!) -> v2.0.0"
  
  local test_dir=$(mktemp -d)
  create_test_repo "$test_dir"
  
  cd "$test_dir"
  echo "breaking change" >> file1.txt
  git add file1.txt
  git commit -q -m "fix!: changed API signature"
  
  # Copy bump script
  mkdir -p scripts
  cp "$BUMP_SCRIPT" scripts/
  
  # Run auto mode
  bash scripts/bump-version.sh auto --allow-dirty >/dev/null 2>&1
  
  if verify_version "2.0.0" "$test_dir" && verify_changelog "2.0.0" "$test_dir"; then
    log_pass "Test F: Breaking change marker correctly bumped to v2.0.0"
  else
    log_fail "Test F: Failed"
  fi
  
  rm -rf "$test_dir"
}

# Test G: feat commit -> v2.0.0 (major trigger)
test_g() {
  log_test "Test G: feat commit -> v2.0.0"
  
  local test_dir=$(mktemp -d)
  create_test_repo "$test_dir"
  
  cd "$test_dir"
  echo "new feature" >> file1.txt
  git add file1.txt
  git commit -q -m "feat: added new API endpoint"
  
  # Copy bump script
  mkdir -p scripts
  cp "$BUMP_SCRIPT" scripts/
  
  # Run auto mode
  bash scripts/bump-version.sh auto --allow-dirty >/dev/null 2>&1
  
  if verify_version "2.0.0" "$test_dir" && verify_changelog "2.0.0" "$test_dir"; then
    log_pass "Test G: feat commit correctly bumped to v2.0.0"
  else
    log_fail "Test G: Failed"
  fi
  
  rm -rf "$test_dir"
}

# Test H: refactor commit -> v2.0.0 (major trigger)
test_h() {
  log_test "Test H: refactor commit -> v2.0.0"
  
  local test_dir=$(mktemp -d)
  create_test_repo "$test_dir"
  
  cd "$test_dir"
  echo "refactor" >> file1.txt
  git add file1.txt
  git commit -q -m "refactor: rewrote authentication system"
  
  # Copy bump script
  mkdir -p scripts
  cp "$BUMP_SCRIPT" scripts/
  
  # Run auto mode
  bash scripts/bump-version.sh auto --allow-dirty >/dev/null 2>&1
  
  if verify_version "2.0.0" "$test_dir" && verify_changelog "2.0.0" "$test_dir"; then
    log_pass "Test H: refactor commit correctly bumped to v2.0.0"
  else
    log_fail "Test H: Failed"
  fi
  
  rm -rf "$test_dir"
}

# Test I: update type commit -> counted as fix
test_i() {
  log_test "Test I: 2 update commits -> v1.1.0"
  
  local test_dir=$(mktemp -d)
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
  
  # Run auto mode
  bash scripts/bump-version.sh auto --allow-dirty >/dev/null 2>&1
  
  if verify_version "1.1.0" "$test_dir" && verify_changelog "1.1.0" "$test_dir"; then
    log_pass "Test I: 2 update commits correctly bumped to v1.1.0"
  else
    log_fail "Test I: Failed"
  fi
  
  rm -rf "$test_dir"
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

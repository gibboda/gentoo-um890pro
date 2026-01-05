#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/bump-version.sh <new-version> "Short changelog entry"
#   ./scripts/bump-version.sh auto [--allow-dirty]
#   ./scripts/bump-version.sh patch|minor|major
# Examples:
#   ./scripts/bump-version.sh 0.1.1 "Fix partition detection"
#   ./scripts/bump-version.sh auto
#   ./scripts/bump-version.sh patch

ALLOW_DIRTY=false

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-dirty)
      ALLOW_DIRTY=true
      shift
      ;;
    *)
      break
      ;;
  esac
done

# Check if git is available
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is not available" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Check if we're in a git repository
if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not in a git repository" >&2
  exit 1
fi

# Check if repo is dirty (unless --allow-dirty is set)
if [[ "$ALLOW_DIRTY" == "false" ]]; then
  if ! git -C "$ROOT_DIR" diff-index --quiet HEAD -- 2>/dev/null; then
    echo "ERROR: repository has uncommitted changes. Use --allow-dirty to override." >&2
    exit 1
  fi
fi

# Function to get the current version from VERSION file
get_current_version() {
  local version_file="$ROOT_DIR/VERSION"
  if [[ -f "$version_file" ]]; then
    tr -d '\r\n' < "$version_file"
  else
    echo "0.0.0"
  fi
}

# Function to find the most recent vX.Y.Z tag
find_latest_tag() {
  git -C "$ROOT_DIR" tag -l "v*.*.*" 2>/dev/null | \
    grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | \
    sort -V | \
    tail -n 1 || echo ""
}

# Function to parse conventional commit type and detect breaking changes
parse_commit() {
  local commit_msg="$1"
  local commit_body="$2"
  
  # Extract the type from commit message (before colon)
  # Handle format: type(scope): message or type!: message or type: message
  local type=""
  local has_breaking=false
  
  # Check for BREAKING CHANGE in body
  if echo "$commit_body" | grep -qi "BREAKING CHANGE"; then
    has_breaking=true
  fi
  
  # Parse type from subject line
  if echo "$commit_msg" | grep -Eq '^[a-z]+(\([^)]+\))?!:'; then
    # Has ! marker (breaking change)
    has_breaking=true
    type=$(echo "$commit_msg" | sed -E 's/^([a-z]+)(\([^)]+\))?!:.*/\1/')
  elif echo "$commit_msg" | grep -Eq '^[a-z]+(\([^)]+\))?:'; then
    # Normal format
    type=$(echo "$commit_msg" | sed -E 's/^([a-z]+)(\([^)]+\))?:.*/\1/')
  fi
  
  echo "$type|$has_breaking"
}

# Function to calculate version bump based on commits
calculate_auto_version() {
  local base_tag="$1"
  local current_version="$2"
  
  # Get commits since tag (or all commits if no tag)
  local commit_range=""
  if [[ -n "$base_tag" ]]; then
    commit_range="${base_tag}..HEAD"
  else
    commit_range="HEAD"
  fi
  
  local fix_count=0
  local has_major_trigger=false
  local commits_data=""
  
  # Parse all commits
  while IFS= read -r commit_sha; do
    if [[ -z "$commit_sha" ]]; then
      continue
    fi
    
    local subject=$(git -C "$ROOT_DIR" show -s --format=%s "$commit_sha")
    local body=$(git -C "$ROOT_DIR" show -s --format=%b "$commit_sha")
    
    local parse_result=$(parse_commit "$subject" "$body")
    local type=$(echo "$parse_result" | cut -d'|' -f1)
    local has_breaking=$(echo "$parse_result" | cut -d'|' -f2)
    
    # Store commit data for changelog
    commits_data="${commits_data}${commit_sha}|${type}|${has_breaking}|${subject}"$'\n'
    
    # Count fixes/updates
    if [[ "$type" == "fix" || "$type" == "update" ]]; then
      ((fix_count++)) || true
    fi
    
    # Check for major triggers
    if [[ "$has_breaking" == "true" ]]; then
      has_major_trigger=true
    elif [[ "$type" == "feat" || "$type" == "refactor" || "$type" == "perf" ]]; then
      has_major_trigger=true
    fi
  done < <(git -C "$ROOT_DIR" rev-list "$commit_range" 2>/dev/null || true)
  
  # Parse current version
  local major minor patch
  if [[ "$current_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    patch="${BASH_REMATCH[3]}"
  else
    major=0
    minor=0
    patch=0
  fi
  
  # Decide bump type
  local bump_type=""
  local new_version=""
  
  if [[ "$has_major_trigger" == "true" ]] || [[ $fix_count -ge 7 ]]; then
    # Major bump
    ((major++)) || true
    minor=0
    patch=0
    bump_type="major"
  elif [[ $fix_count -ge 2 && $fix_count -le 6 ]]; then
    # Minor bump
    ((minor++)) || true
    patch=0
    bump_type="minor"
  else
    # Patch bump (0-1 fixes)
    ((patch++)) || true
    bump_type="patch"
  fi
  
  new_version="${major}.${minor}.${patch}"
  
  # Output results on separate lines to avoid issues with multiline data
  echo "NEW_VERSION=${new_version}"
  echo "BUMP_TYPE=${bump_type}"
  echo "FIX_COUNT=${fix_count}"
  echo "BASE_TAG=${base_tag}"
  echo "COMMITS_DATA_START"
  echo -n "$commits_data"
  echo "COMMITS_DATA_END"
}

# Function to update CHANGELOG.md with grouped sections
update_changelog_auto() {
  local new_version="$1"
  local commits_data="$2"
  local changelog_file="$ROOT_DIR/CHANGELOG.md"
  
  local date_str=$(date -u +"%Y-%m-%d")
  
  # Group commits by type
  local fixes=""
  local changes=""
  local performance=""
  local refactors=""
  local other=""
  
  while IFS='|' read -r commit_sha type has_breaking subject; do
    if [[ -z "$commit_sha" ]]; then
      continue
    fi
    
    local entry="- $subject"
    
    case "$type" in
      fix|update)
        fixes="${fixes}${entry}"$'\n'
        ;;
      feat)
        changes="${changes}${entry}"$'\n'
        ;;
      perf)
        performance="${performance}${entry}"$'\n'
        ;;
      refactor)
        refactors="${refactors}${entry}"$'\n'
        ;;
      docs|test|chore|style|build|ci)
        # Skip these types
        ;;
      *)
        if [[ -n "$type" ]]; then
          other="${other}${entry}"$'\n'
        fi
        ;;
    esac
  done <<< "$commits_data"
  
  # Build release section
  local release_section="## [${new_version}] - ${date_str}"$'\n'
  
  if [[ -n "$fixes" ]]; then
    release_section="${release_section}"$'\n'"### Fixes"$'\n'"${fixes}"
  fi
  if [[ -n "$changes" ]]; then
    release_section="${release_section}"$'\n'"### Changes"$'\n'"${changes}"
  fi
  if [[ -n "$performance" ]]; then
    release_section="${release_section}"$'\n'"### Performance"$'\n'"${performance}"
  fi
  if [[ -n "$refactors" ]]; then
    release_section="${release_section}"$'\n'"### Refactors"$'\n'"${refactors}"
  fi
  if [[ -n "$other" ]]; then
    release_section="${release_section}"$'\n'"### Other"$'\n'"${other}"
  fi
  
  # If no entries, add maintenance note
  if [[ -z "$fixes" && -z "$changes" && -z "$performance" && -z "$refactors" && -z "$other" ]]; then
    release_section="${release_section}"$'\n'"- Maintenance release."$'\n'
  fi
  
  # Update or create CHANGELOG.md
  if [[ -f "$changelog_file" ]]; then
    local tmpfile=$(mktemp)
    if grep -Eq '^##[[:space:]]+\[?Unreleased\]?' "$changelog_file"; then
      # Insert after Unreleased header
      awk -v section="$release_section" '
        BEGIN { inserted=0 }
        inserted==0 && ($0 ~ /^##[[:space:]]+\[?Unreleased\]?/) {
          print
          print ""
          printf "%s", section
          inserted=1
          next
        }
        { print }
      ' "$changelog_file" > "$tmpfile"
    else
      # Prepend Unreleased section and release section
      {
        echo "## [Unreleased]"
        echo ""
        printf "%s" "$release_section"
        echo ""
        cat "$changelog_file"
      } > "$tmpfile"
    fi
    mv "$tmpfile" "$changelog_file"
  else
    # Create new CHANGELOG.md
    {
      echo "# Changelog"
      echo ""
      echo "## [Unreleased]"
      echo ""
      printf "%s" "$release_section"
      echo ""
    } > "$changelog_file"
  fi
}

# Auto mode implementation
if [[ ${#} -ge 1 && "$1" == "auto" ]]; then
  OLD_VERSION=$(get_current_version)
  BASE_TAG=$(find_latest_tag)
  
  # Calculate new version - capture output
  AUTO_OUTPUT=$(calculate_auto_version "$BASE_TAG" "$OLD_VERSION")
  
  # Parse output
  NEW_VERSION=$(echo "$AUTO_OUTPUT" | grep "^NEW_VERSION=" | cut -d= -f2-)
  BUMP_TYPE=$(echo "$AUTO_OUTPUT" | grep "^BUMP_TYPE=" | cut -d= -f2-)
  FIX_COUNT=$(echo "$AUTO_OUTPUT" | grep "^FIX_COUNT=" | cut -d= -f2-)
  BASE_TAG_USED=$(echo "$AUTO_OUTPUT" | grep "^BASE_TAG=" | cut -d= -f2-)
  
  # Extract commits data between markers
  COMMITS_DATA=$(echo "$AUTO_OUTPUT" | sed -n '/^COMMITS_DATA_START$/,/^COMMITS_DATA_END$/p' | sed '1d;$d')
  
  # Update CHANGELOG.md
  update_changelog_auto "$NEW_VERSION" "$COMMITS_DATA"
  
  # Update VERSION file
  echo "$NEW_VERSION" > "$ROOT_DIR/VERSION"
  
  # Update installer file
  INSTALLER_FILE="$ROOT_DIR/gentoo-um890pro-install.sh"
  if [[ -f "$INSTALLER_FILE" ]]; then
    # Use sed with portable syntax for macOS/Linux
    if sed --version >/dev/null 2>&1; then
      # GNU sed
      sed -i "1,/^VERSION=/s/^VERSION=.*/VERSION=\"$NEW_VERSION\"/" "$INSTALLER_FILE"
    else
      # BSD sed (macOS)
      sed -i '' "1,/^VERSION=/s/^VERSION=.*/VERSION=\"$NEW_VERSION\"/" "$INSTALLER_FILE"
    fi
  fi
  
  # Print summary
  echo "Auto version bump completed:"
  echo "  Old version: $OLD_VERSION"
  echo "  New version: $NEW_VERSION"
  echo "  Bump type: $BUMP_TYPE"
  echo "  Base tag: ${BASE_TAG_USED:-none}"
  echo "  Fix/update count: $FIX_COUNT"
  echo "  Changed files:"
  echo "    - VERSION"
  echo "    - CHANGELOG.md"
  if [[ -f "$INSTALLER_FILE" ]]; then
    echo "    - gentoo-um890pro-install.sh"
  fi
  
  exit 0
fi

# Patch/minor/major mode
if [[ ${#} -eq 1 && ("$1" == "patch" || "$1" == "minor" || "$1" == "major") ]]; then
  BUMP_TYPE="$1"
  OLD_VERSION=$(get_current_version)
  
  # Parse current version
  if [[ "$OLD_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    patch="${BASH_REMATCH[3]}"
  else
    major=0
    minor=0
    patch=0
  fi
  
  case "$BUMP_TYPE" in
    major)
      ((major++)) || true
      minor=0
      patch=0
      ;;
    minor)
      ((minor++)) || true
      patch=0
      ;;
    patch)
      ((patch++)) || true
      ;;
  esac
  
  NEW_VERSION="${major}.${minor}.${patch}"
  MSG="$BUMP_TYPE version bump"
else
  # Manual version mode (original behavior)
  if [[ ${#} -lt 2 ]]; then
    echo "Usage: $0 <new-version> \"Short changelog entry\"" >&2
    echo "       $0 auto [--allow-dirty]" >&2
    echo "       $0 patch|minor|major" >&2
    exit 1
  fi

  NEW_VERSION="$1"
  shift
  MSG="$*"

  if ! echo "$NEW_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "ERROR: version must be in X.Y.Z semantic version format (got: $NEW_VERSION)" >&2
    exit 1
  fi
fi

# Manual mode: update files with explicit version/message
VERSION_FILE="$ROOT_DIR/VERSION"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"
INSTALLER_FILE="$ROOT_DIR/gentoo-um890pro-install.sh"

echo "$NEW_VERSION" > "$VERSION_FILE"

if [[ -f "$INSTALLER_FILE" ]]; then
  # Use sed with portable syntax for macOS/Linux
  if sed --version >/dev/null 2>&1; then
    # GNU sed
    sed -i "1,/^VERSION=/s/^VERSION=.*/VERSION=\"$NEW_VERSION\"/" "$INSTALLER_FILE"
  else
    # BSD sed (macOS)
    sed -i '' "1,/^VERSION=/s/^VERSION=.*/VERSION=\"$NEW_VERSION\"/" "$INSTALLER_FILE"
  fi
fi

date_str=$(date -u +"%Y-%m-%d")

if [[ -f "$CHANGELOG_FILE" ]]; then
  tmpfile=$(mktemp)
  if grep -Eq '^##[[:space:]]+\[?Unreleased\]?' "$CHANGELOG_FILE"; then
    # Insert after Unreleased header
    awk -v d="$date_str" -v v="$NEW_VERSION" -v m="$MSG" '
      BEGIN { inserted=0 }
      # Insert immediately after the first Unreleased header (supports "## [Unreleased]" or "## Unreleased")
      inserted==0 && ($0 ~ /^##[[:space:]]+\[?Unreleased\]?/) {
        print
        print ""
        print "## [" v "] - " d
        print "- " m
        print ""
        inserted=1
        next
      }
      { print }
    ' "$CHANGELOG_FILE" > "$tmpfile"
  else
    # Prepend entry to the top if no Unreleased section exists
    {
      echo "## [$NEW_VERSION] - $date_str"
      echo "- $MSG"
      echo ""
      cat "$CHANGELOG_FILE"
    } > "$tmpfile"
  fi
  mv "$tmpfile" "$CHANGELOG_FILE"
else
  {
    echo "# Changelog"
    echo ""
    echo "## [Unreleased]"
    echo ""
    echo "## [$NEW_VERSION] - $date_str"
    echo "- $MSG"
    echo ""
  } > "$CHANGELOG_FILE"
fi

if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [[ -f "$INSTALLER_FILE" ]]; then
    git -C "$ROOT_DIR" add "$VERSION_FILE" "$CHANGELOG_FILE" "$INSTALLER_FILE"
  else
    git -C "$ROOT_DIR" add "$VERSION_FILE" "$CHANGELOG_FILE"
  fi
  git -C "$ROOT_DIR" commit -m "Bump version: $NEW_VERSION - $MSG" || true
  git -C "$ROOT_DIR" tag -a "v$NEW_VERSION" -m "$MSG" || true
  echo "Committed and tagged v$NEW_VERSION"
fi

echo "Bumped version to $NEW_VERSION"

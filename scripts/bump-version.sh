#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/bump-version.sh <new-version> "Short changelog entry"
# Example:
#   ./scripts/bump-version.sh 0.1.1 "Fix partition detection"

if [[ ${#} -lt 2 ]]; then
  echo "Usage: $0 <new-version> \"Short changelog entry\"" >&2
  exit 1
fi

NEW_VERSION="$1"
shift
MSG="$*"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"
INSTALLER_FILE="$ROOT_DIR/gentoo-um890pro-install.sh"

echo "$NEW_VERSION" > "$VERSION_FILE"

if [[ -f "$INSTALLER_FILE" ]]; then
  tmpfile_installer=$(mktemp)
  awk -v v="$NEW_VERSION" '
    BEGIN { updated=0 }
    updated==0 && $0 ~ /^VERSION="[^"]*"/ {
      print "VERSION=\"" v "\""
      updated=1
      next
    }
    { print }
  ' "$INSTALLER_FILE" > "$tmpfile_installer"
  mv "$tmpfile_installer" "$INSTALLER_FILE"
fi

date_str=$(date -u +"%Y-%m-%d")

if [[ -f "$CHANGELOG_FILE" ]]; then
  tmpfile=$(mktemp)
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

  if grep -Eq '^##[[:space:]]+\[?Unreleased\]?' "$CHANGELOG_FILE"; then
    mv "$tmpfile" "$CHANGELOG_FILE"
  else
    # Prepend entry to the top if no Unreleased section exists.
    tmpfile2=$(mktemp)
    {
      echo "## [$NEW_VERSION] - $date_str"
      echo "- $MSG"
      echo ""
      cat "$CHANGELOG_FILE"
    } > "$tmpfile2"
    mv "$tmpfile2" "$CHANGELOG_FILE"
    rm -f "$tmpfile"
  fi
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

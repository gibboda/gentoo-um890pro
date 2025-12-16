#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/bump-version.sh <new-version> "Short changelog entry"
# Example: ./scripts/bump-version.sh 0.1.1 "Fix partition detection"

if [[ ${#} -lt 2 ]]; then
  echo "Usage: $0 <new-version> \"Short changelog entry\""
  exit 1
fi

NEW_VERSION="$1"
shift
MSG="$*"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
CHANGELOG="$ROOT_DIR/CHANGELOG.md"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "0.0.0" > "$VERSION_FILE"
fi

OLD_VERSION=$(cat "$VERSION_FILE" | tr -d '\n')

# Update VERSION file
echo "$NEW_VERSION" > "$VERSION_FILE"

date_str=$(date -u +"%Y-%m-%d")

# Prepend changelog entry under Unreleased
if grep -q "^## Unreleased" "$CHANGELOG" 2>/dev/null; then
  tmpfile=$(mktemp)
  awk -v d="$date_str" -v v="$NEW_VERSION" -v m="$MSG" '
    BEGIN{printed=0}
    /^## Unreleased/ { print; print ""; print "## [" v "] - " d; print "- " m; print ""; printed=1; next }
    { print }
  ' "$CHANGELOG" > "$tmpfile" && mv "$tmpfile" "$CHANGELOG"
else
  # Fallback: append to top
  tmpfile=$(mktemp)
  echo "## [$NEW_VERSION] - $date_str" > "$tmpfile"
  echo "- $MSG" >> "$tmpfile"
  echo "" >> "$tmpfile"
  cat "$CHANGELOG" >> "$tmpfile"
  mv "$tmpfile" "$CHANGELOG"
fi

# Commit & tag if in a git repo
if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT_DIR" add "$VERSION_FILE" "$CHANGELOG"
  git -C "$ROOT_DIR" commit -m "Bump version: $NEW_VERSION - $MSG" || true
  git -C "$ROOT_DIR" tag -a "v$NEW_VERSION" -m "$MSG" || true
  echo "Committed and tagged v$NEW_VERSION"
else
  echo "Updated $VERSION_FILE and $CHANGELOG (not a git repo)."
fi

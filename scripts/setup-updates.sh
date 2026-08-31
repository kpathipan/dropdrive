#!/bin/bash
# One-time setup: creates the public GitHub repository the updater reads,
# switches update checking on, and publishes the current version as its first
# release.
#
# Run `gh auth login` first — that step needs your GitHub account and can't be
# automated. Everything after it is handled here.
#
#   ./scripts/setup-updates.sh            # publishes source + releases
#   ./scripts/setup-updates.sh --dmg-only # publishes releases only, no source
set -euo pipefail

cd "$(dirname "$0")/.."

REPO_NAME="dropdrive"
DMG_ONLY=false
[ "${1:-}" = "--dmg-only" ] && DMG_ONLY=true

command -v gh >/dev/null 2>&1 || { echo "error: gh is not installed. Run: brew install gh" >&2; exit 1; }

if ! gh auth status >/dev/null 2>&1; then
  echo "error: not signed in to GitHub. Run this first, then re-run me:" >&2
  echo "       gh auth login" >&2
  exit 1
fi

OWNER=$(gh api user --jq .login)
REPO="$OWNER/$REPO_NAME"
VERSION=$(grep -m1 -oE 'MARKETING_VERSION = [0-9.]+' DropDrive.xcodeproj/project.pbxproj | grep -oE '[0-9.]+')
echo "==> Account: $OWNER"
echo "==> Repository: $REPO"
echo "==> Version to publish: $VERSION"

if gh repo view "$REPO" >/dev/null 2>&1; then
  echo "==> Repository already exists, reusing it"
else
  echo "==> Creating the public repository"
  gh repo create "$REPO" --public --description "Download Google Drive files and folders directly to your Mac."
fi

echo "==> Switching update checking on"
sed -i '' "s|nonisolated static let repository = \"[^\"]*\"|nonisolated static let repository = \"$REPO\"|" \
  DropDrive/Services/UpdateService.swift
grep -q "repository = \"$REPO\"" DropDrive/Services/UpdateService.swift \
  || { echo "error: could not set the repository constant" >&2; exit 1; }

git add DropDrive/Services/UpdateService.swift
git commit -qm "Point the updater at $REPO" || true

if [ "$DMG_ONLY" = true ]; then
  # Releases only: the repository holds the DMG and the changelog, not the code.
  echo "==> Publishing releases only (no source)"
  git remote remove origin 2>/dev/null || true
else
  echo "==> Publishing the source"
  git remote remove origin 2>/dev/null || true
  git remote add origin "https://github.com/$REPO.git"
  git push -u origin HEAD
fi

echo "==> Rebuilding $VERSION with update checking enabled"
./scripts/test-keychain-isolation.sh
./scripts/test-performance-improvements.sh
./scripts/test-regressions.sh
./scripts/build-dmg.sh >/dev/null
DMG="dist/DropDrive-v$VERSION.dmg"
[ -f "$DMG" ] || { echo "error: expected $DMG" >&2; exit 1; }

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
NOTES=$(mktemp)
awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" { inside = 1; next }
  inside && /^## \[/ { exit }
  inside { print }
' CHANGELOG.md > "$NOTES"
printf '\nsha256: %s\n' "$SHA" >> "$NOTES"

echo "==> Publishing release v$VERSION"
git tag -f "v$VERSION"
[ "$DMG_ONLY" = true ] || git push origin --tags
gh release create "v$VERSION" "$DMG" \
  --repo "$REPO" \
  --title "DropDrive $VERSION" \
  --notes-file "$NOTES"
rm -f "$NOTES"

echo
echo "==> Done."
echo "    Release:  https://github.com/$REPO/releases/latest"
echo "    Send $DMG to your friends once more; after that they update in place."
echo "    Future versions: ./scripts/release.sh <version>"

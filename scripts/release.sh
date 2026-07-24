#!/bin/bash
# Publishes a new version: bumps the version number, builds the DMG, computes
# its checksum, and creates the GitHub Release the app's updater reads.
#
#   ./scripts/release.sh 6.12.0
#
# Needs the GitHub CLI once:  brew install gh && gh auth login
#
# The app finds updates through GitHub's "latest release" API, so what matters
# here is that the release is tagged vX.Y.Z, has the DMG attached, and carries a
# "sha256: <hex>" line in its notes — UpdateService refuses to install anything
# whose bytes don't match that line.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 <version>   e.g. $0 6.12.0" >&2
  exit 1
fi

REPO=$(grep -oE 'nonisolated static let repository = "[^"]*"' DropDrive/Services/UpdateService.swift | sed 's/.*"\(.*\)"/\1/')
if [ -z "$REPO" ]; then
  echo "error: no repository set in DropDrive/Services/UpdateService.swift." >&2
  echo "       Set 'repository' to \"owner/name\" first, or friends' apps will never see this release." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "error: the GitHub CLI is not installed. Run: brew install gh && gh auth login" >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree has uncommitted changes. Commit them first." >&2
  exit 1
fi

echo "==> Setting version to $VERSION"
sed -i '' "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $VERSION;/g" DropDrive.xcodeproj/project.pbxproj
git add DropDrive.xcodeproj/project.pbxproj
git commit -qm "Release v$VERSION" || true

echo "==> Building the DMG"
./scripts/build-dmg.sh >/dev/null

DMG="dist/DropDrive-v$VERSION-adhoc.dmg"
[ -f "$DMG" ] || { echo "error: expected $DMG, which the build did not produce" >&2; exit 1; }

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
SIZE=$(du -h "$DMG" | cut -f1)
echo "==> $DMG ($SIZE)"
echo "    sha256: $SHA"

# The section for this version out of CHANGELOG.md becomes the release notes,
# and the app shows the first few lines of it on the update card.
NOTES_FILE=$(mktemp)
awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" { inside = 1; next }
  inside && /^## \[/ { exit }
  inside { print }
' CHANGELOG.md > "$NOTES_FILE"
printf '\nsha256: %s\n' "$SHA" >> "$NOTES_FILE"

echo "==> Publishing v$VERSION to $REPO"
git tag -f "v$VERSION"
git push origin HEAD --tags
gh release create "v$VERSION" "$DMG" \
  --repo "$REPO" \
  --title "DropDrive $VERSION" \
  --notes-file "$NOTES_FILE"
rm -f "$NOTES_FILE"

echo "==> Done. Installed copies will offer this update within a day."

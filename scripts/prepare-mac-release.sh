#!/bin/bash
# Local signed Mac artifact preparation only. Never tags, pushes or publishes.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: bash scripts/prepare-mac-release.sh X.Y.Z" >&2; exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Commit source changes before preparing paired artifacts." >&2; exit 1
fi
SOURCE_COMMIT=$(git rev-parse HEAD)
PROJECT_VERSION=$(sed -nE 's/.*MARKETING_VERSION = ([0-9.]+);/\1/p' DropDrive.xcodeproj/project.pbxproj | sort -u)
if [ "$PROJECT_VERSION" != "$VERSION" ]; then
  echo "Set and commit the same version for app/extension before preparing the pair." >&2; exit 1
fi
bash scripts/test-keychain-isolation.sh
bash scripts/test-performance-improvements.sh
bash scripts/test-regressions.sh
bash scripts/offline-harness/run.sh
bash scripts/test-media-reliability.sh --fake-extractor
bash scripts/build-dmg.sh
if security find-identity -v -p codesigning | grep -q 'Developer ID Application'; then
  bash scripts/notarize-release.sh "dist/DropDrive-v$VERSION.dmg"
fi
ruby scripts/write-mac-receipt.rb "$VERSION" "$SOURCE_COMMIT"

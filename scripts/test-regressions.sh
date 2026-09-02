#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc -O \
  DropDrive/Utilities/DestinationCapacity.swift \
  DropDrive/Utilities/GoogleDriveLinkParser.swift \
  DropDrive/Utilities/LinkIdentity.swift \
  DropDrive/Utilities/SupportedLinkExtractor.swift \
  DropDrive/Utilities/TikTokPlayerMedia.swift \
  DropDriveShare/ShareLinkExtractor.swift \
  DropDrive/Models/ExternalLinkReceipt.swift \
  DropDrive/Models/DownloadProgress.swift \
  DropDrive/Models/DriveLinkAnalysis.swift \
  DropDrive/Models/QueueItem.swift \
  DropDrive/Services/AppLanguage.swift \
  DropDrive/Utilities/UniqueDestinationNaming.swift \
  DropDrive/Utilities/SecurityScopedAccessManager.swift \
  DropDrive/Utilities/SecurityScopedBookmark.swift \
  scripts/regression-harness/main.swift \
  -o "$OUT/regression-harness"

"$OUT/regression-harness"

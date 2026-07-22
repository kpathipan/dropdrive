#!/bin/bash
# Exercises the real download engine against a stubbed Google Drive, with no
# network, no credentials, and no app bundle. There is no Xcode test target, so
# this compiles the actual source files into a throwaway executable instead.
#
# Covers: folder analysis (counts, bytes, category breakdown, parallel scan,
# concurrency cap, shortcut cycles), folder download (every file byte-identical,
# no staging files left), resume (only missing files re-fetched), and multi-part
# ranged downloads (byte-identical, correct range count, probe cached per host).
set -euo pipefail

cd "$(dirname "$0")/../.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc -O -swift-version 5 -default-isolation MainActor \
  DropDrive/Services/DownloadService.swift \
  DropDrive/Models/DownloadRequest.swift \
  DropDrive/Models/DownloadProgress.swift \
  DropDrive/Models/DriveLinkAnalysis.swift \
  DropDrive/Utilities/FileCategoryClassifier.swift \
  DropDrive/Utilities/UniqueDestinationNaming.swift \
  DropDrive/Utilities/Formatters.swift \
  DropDrive/Services/ResumeEnvelopeStore.swift \
  scripts/offline-harness/Stubs.swift \
  scripts/offline-harness/main.swift \
  -o "$OUT/harness"

"$OUT/harness"

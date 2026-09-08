#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MEDIA_TEST_DIR=$(mktemp -d -t dropdrive-media-tests)
trap 'rm -rf "$MEDIA_TEST_DIR"' EXIT
APP="$MEDIA_TEST_DIR/MediaHarness.app/Contents"
mkdir -p "$APP/MacOS" "$APP/Resources"
for tool in yt-dlp ffmpeg deno; do
  ln -s "$PWD/DropDrive/Tools/$tool" "$APP/Resources/$tool"
done
if [[ " $* " == *" --fake-extractor "* ]]; then
  unlink "$APP/Resources/yt-dlp"
  xcrun swiftc scripts/media-harness/FakeExtractor.swift -o "$APP/Resources/yt-dlp"
fi
xcrun swiftc -O -swift-version 5 -enable-bare-slash-regex -default-isolation MainActor \
  DropDrive/Services/VideoDownloadService.swift \
  DropDrive/Services/TransferGuard.swift \
  DropDrive/Services/TempCleaner.swift \
  DropDrive/Models/DownloadProgress.swift \
  DropDrive/Models/DriveLinkAnalysis.swift \
  DropDrive/Utilities/VideoDownloadPolicy.swift \
  DropDrive/Utilities/VideoProcessLifetime.swift \
  DropDrive/Utilities/SupportedLinkExtractor.swift \
  DropDrive/Utilities/GoogleDriveLinkParser.swift \
  DropDrive/Utilities/LinkIdentity.swift \
  DropDrive/Utilities/TikTokPlayerMedia.swift \
  DropDrive/Utilities/UniqueDestinationNaming.swift \
  DropDrive/Utilities/DestinationCapacity.swift \
  scripts/media-harness/Stubs.swift scripts/media-harness/main.swift \
  -o "$APP/MacOS/MediaHarness"
"$APP/MacOS/MediaHarness" "$@"

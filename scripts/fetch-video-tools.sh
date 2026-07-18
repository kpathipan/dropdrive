#!/bin/bash
# Downloads the video-download engine binaries DropDrive bundles:
#   - yt-dlp   (official standalone macOS build, universal2)
#   - ffmpeg   (static builds per-arch from martin-riedl.de, lipo'd universal;
#               needed by yt-dlp to merge YouTube's separate video+audio tracks)
# Output goes to DropDrive/Tools/, which the Xcode project bundles as resources.
# Binaries are gitignored — run this once per checkout (and re-run to update).
set -euo pipefail

cd "$(dirname "$0")/.."
TOOLS_DIR="DropDrive/Tools"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

mkdir -p "$TOOLS_DIR"

echo "==> yt-dlp (universal2)"
curl -fL --progress-bar -o "$TOOLS_DIR/yt-dlp" \
  "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
chmod +x "$TOOLS_DIR/yt-dlp"

echo "==> ffmpeg arm64"
curl -fL --progress-bar -o "$SCRATCH/ffmpeg-arm64.zip" \
  "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip"
unzip -q -o "$SCRATCH/ffmpeg-arm64.zip" -d "$SCRATCH/arm64"

echo "==> ffmpeg x86_64"
curl -fL --progress-bar -o "$SCRATCH/ffmpeg-amd64.zip" \
  "https://ffmpeg.martin-riedl.de/redirect/latest/macos/amd64/release/ffmpeg.zip"
unzip -q -o "$SCRATCH/ffmpeg-amd64.zip" -d "$SCRATCH/amd64"

echo "==> lipo universal ffmpeg"
lipo -create "$SCRATCH/arm64/ffmpeg" "$SCRATCH/amd64/ffmpeg" -output "$TOOLS_DIR/ffmpeg"
chmod +x "$TOOLS_DIR/ffmpeg"

echo "==> Verifying"
"$TOOLS_DIR/yt-dlp" --version
lipo -archs "$TOOLS_DIR/ffmpeg"
"$TOOLS_DIR/ffmpeg" -version | head -1
ls -lh "$TOOLS_DIR"
echo "==> Done"

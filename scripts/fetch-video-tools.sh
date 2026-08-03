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

# Both tools have to stay universal, and this is where that can quietly stop
# being true: they're fetched from upstream, not built here. macOS 27 is Apple
# Silicon only and Rosetta goes away entirely in macOS 28, so upstream projects
# will start shipping arm64-only builds — at which point a fetch would succeed,
# the app would build, build-dmg.sh's universal check would pass (it only looks
# at our own binary), and video downloads would simply fail on any friend still
# on an Intel Mac. Fail here instead, while there's something to be done about it.
for TOOL in yt-dlp ffmpeg; do
  TOOL_ARCHS=$(lipo -archs "$TOOLS_DIR/$TOOL" 2>/dev/null || echo "unreadable")
  echo "    $TOOL: $TOOL_ARCHS"
  case "$TOOL_ARCHS" in
    *arm64*x86_64*|*x86_64*arm64*) ;;
    *)
      echo "Refusing to continue: $TOOL is '$TOOL_ARCHS', not universal." >&2
      echo "Upstream has likely dropped Intel builds. Video downloads would fail" >&2
      echo "on Intel Macs, which cannot run macOS 27 and are staying on macOS 26." >&2
      exit 1
      ;;
  esac
done

"$TOOLS_DIR/yt-dlp" --version
"$TOOLS_DIR/ffmpeg" -version | head -1
ls -lh "$TOOLS_DIR"
echo "==> Done"

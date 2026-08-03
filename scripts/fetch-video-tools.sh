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

# Apple Silicon only — see the note in build-dmg.sh. The Intel slice was 90 MB
# of ffmpeg on its own. To go back to universal, fetch the amd64 zip as well
# and `lipo -create` the two together.
echo "==> ffmpeg arm64"
curl -fL --progress-bar -o "$SCRATCH/ffmpeg-arm64.zip" \
  "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip"
unzip -q -o "$SCRATCH/ffmpeg-arm64.zip" -d "$SCRATCH/arm64"
cp "$SCRATCH/arm64/ffmpeg" "$TOOLS_DIR/ffmpeg"
chmod +x "$TOOLS_DIR/ffmpeg"

echo "==> Verifying"

# Both tools have to cover the architectures the app ships for. They're fetched
# from upstream, not built here, so this is where a silent change would land —
# and a tool that can't run is a broken feature rather than a broken launch,
# which is harder to notice.
REQUIRED_ARCH="arm64"
for TOOL in yt-dlp ffmpeg; do
  TOOL_ARCHS=$(lipo -archs "$TOOLS_DIR/$TOOL" 2>/dev/null || echo "unreadable")
  echo "    $TOOL: $TOOL_ARCHS"
  case " $TOOL_ARCHS " in
    *" $REQUIRED_ARCH "*) ;;
    *)
      echo "Refusing to continue: $TOOL is '$TOOL_ARCHS', missing '$REQUIRED_ARCH'." >&2
      exit 1
      ;;
  esac
done

"$TOOLS_DIR/yt-dlp" --version
"$TOOLS_DIR/ffmpeg" -version | head -1
ls -lh "$TOOLS_DIR"
echo "==> Done"

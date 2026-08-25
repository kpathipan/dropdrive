#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

ALLOW_ADHOC=false
case "${1:-}" in
  "") ;;
  --allow-adhoc) ALLOW_ADHOC=true ;;
  *) echo "usage: $0 [--allow-adhoc]" >&2; exit 1 ;;
esac
if [ -n "${2:-}" ]; then
  echo "usage: $0 [--allow-adhoc]" >&2
  exit 1
fi

VERSION=$(grep -m1 'MARKETING_VERSION' DropDrive.xcodeproj/project.pbxproj | sed -E 's/.*= ([0-9.]+);/\1/')

# Apple Silicon only from 6.13.0. macOS 27 dropped Intel Macs entirely and
# Rosetta goes in macOS 28, so an Intel build serves machines that are already
# frozen on macOS 26 — and nobody using this app is on one. Dropping the slice
# halves the download: 201 MB to 106 MB, ffmpeg alone 152 MB to 62 MB.
#
# Anyone who does end up on an Intel Mac is protected rather than broken:
# UpdateService refuses to install a build this machine can't execute, so an
# older universal copy keeps running instead of being replaced by one that
# won't launch. Put x86_64 back here and re-run fetch-video-tools.sh to reverse
# this.
TARGET_ARCHS="arm64"
BUILD_DIR="build-adhoc"
STAGING_DIR="$BUILD_DIR/staging"
RW_DMG="$BUILD_DIR/DropDrive-rw.dmg"
FINAL_DMG="dist/DropDrive-v${VERSION}-adhoc.dmg"
VOLUME_NAME="DropDrive"
WINDOW_WIDTH=620
WINDOW_HEIGHT=650
APP_ICON_POS="180, 155"
APPLICATIONS_ICON_POS="440, 155"
NOTE_ICON_POS="310, 520"

echo "==> Building DropDrive v${VERSION} (ad-hoc, unsigned build product)"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$STAGING_DIR" dist

# Left to itself, xcodebuild picks the first matching destination — this Mac,
# i.e. arm64 — and ships an Apple-Silicon-only binary that simply won't launch
# on an Intel Mac. A generic destination plus explicit ARCHS forces the
# universal build a distributable DMG needs.
xcodebuild -scheme DropDrive -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -destination 'generic/platform=macOS' \
  ARCHS="$TARGET_ARCHS" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build | tail -20

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/DropDrive.app"
APPEX_PATH="$APP_PATH/Contents/PlugIns/DropDriveShare.appex"

if [ ! -d "$APP_PATH" ]; then
  echo "Build failed: $APP_PATH not found" >&2
  exit 1
fi

# Signing identity. A stable one matters for more than tidiness: an ad-hoc
# signature identifies the app by the hash of its binary, so every build looks
# like a different application to the system — and the keychain then demands the
# login password before handing the new build the Google session the old one
# saved. Signing with a certificate makes the identity the certificate instead,
# which is the same across builds, so the grant survives an update.
#
# This is an Apple Development certificate, which comes free with any Apple ID
# through Xcode; it is not the paid Developer Program, and it does not make the
# app pass Gatekeeper — quarantine still has to be cleared on first launch.
# A distributable build must never silently fall back to ad-hoc: that would
# replace the stable requirement with a changing binary hash and make every
# user's keychain ask for a password on the next launch. Developers can opt in
# explicitly with --allow-adhoc for a local-only package.
SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -oE '"Apple Develop(ment|er ID Application)[^"]*"' | head -1 | tr -d '"')
# A secure timestamp, countersigned by Apple, is what keeps a signature valid
# after the certificate behind it expires. Without one the signature is only
# good for the certificate's own lifetime — and since the in-app updater
# verifies every download's signature before installing it, an expired
# certificate would otherwise make every future update uninstallable, on every
# friend's Mac at once. Ad-hoc signatures can't be timestamped, hence the split.
TIMESTAMP_FLAG=()
if [ -n "$SIGN_ID" ]; then
  echo "==> Signing as: $SIGN_ID"
  TIMESTAMP_FLAG=(--timestamp)
else
  if [ "$ALLOW_ADHOC" = false ]; then
    echo "Refusing to package: no Apple Development signing certificate was found." >&2
    echo "An ad-hoc update changes the app identity and makes users enter their keychain password." >&2
    echo "For a local-only DMG, run: $0 --allow-adhoc" >&2
    exit 1
  fi
  SIGN_ID="-"
  echo "==> No signing certificate found; using explicitly requested ad-hoc signing"
  echo "    This DMG is local-only and must never be published as an update."
fi

# Pin the app's identity to the Team ID rather than to this particular
# certificate. macOS derives an app's identity from its designated requirement,
# and the default one names the certificate's common name — which carries a
# per-certificate id, so renewing the certificate next July would produce a
# different identity and cost everyone the keychain password one more time. The
# Team ID belongs to the Apple ID, not to any one certificate, so pinning to it
# survives renewals indefinitely.
#
# Signed inside-out rather than with --deep on the outer bundle: --deep would
# force this requirement onto the nested code too, and the app extension has its
# own identifier, so the nested signatures come out invalid.
REQUIREMENT=""
if [ "$SIGN_ID" != "-" ]; then
  TEAM_ID=$(security find-certificate -c "$SIGN_ID" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU ?= ?[A-Z0-9]+' | grep -oE '[A-Z0-9]{10}' | head -1)
  if [ -n "$TEAM_ID" ]; then
    REQUIREMENT="designated => identifier \"com.dropdrive.DropDrive\" and anchor apple generic and certificate leaf[subject.OU] = \"$TEAM_ID\""
    echo "==> Pinning identity to Team ID: $TEAM_ID"
  else
    echo "Refusing to package: could not read a Team ID from '$SIGN_ID'." >&2
    echo "Without the Team-ID requirement, a certificate renewal would trigger a keychain prompt." >&2
    exit 1
  fi
fi

for TOOL in "$APP_PATH/Contents/Resources/ffmpeg" "$APP_PATH/Contents/Resources/yt-dlp" "$APP_PATH/Contents/Resources/deno"; do
  [ -f "$TOOL" ] && codesign --force --sign "$SIGN_ID" "${TIMESTAMP_FLAG[@]}" "$TOOL"
done

if [ -d "$APPEX_PATH" ]; then
  codesign --force --deep --sign "$SIGN_ID" "${TIMESTAMP_FLAG[@]}" \
    --entitlements DropDriveShare/DropDriveShare.entitlements \
    "$APPEX_PATH"
fi

REQUIREMENT_FLAG=()
[ -n "$REQUIREMENT" ] && REQUIREMENT_FLAG=(-r="$REQUIREMENT")
codesign --force --sign "$SIGN_ID" "${TIMESTAMP_FLAG[@]}" "${REQUIREMENT_FLAG[@]}" \
  --entitlements packaging/DropDrive-adhoc.entitlements \
  "$APP_PATH"

echo "==> Verifying nested code survived"
codesign -v --deep --strict "$APP_PATH" || { echo "Refusing to ship: deep signature verification failed." >&2; exit 1; }

# Captured rather than piped into grep: `grep -q` closes the pipe on its first
# match, codesign dies of SIGPIPE, and `set -o pipefail` then reports the whole
# pipeline as failed — so the check fired precisely when it should have passed.
if [ "$SIGN_ID" != "-" ]; then
  SIGNATURE_INFO=$(codesign -dvvv "$APP_PATH" 2>&1 || true)
  case "$SIGNATURE_INFO" in
    *"Timestamp="*) ;;
    *)
      echo "Refusing to ship: the signature has no secure timestamp, so it would stop verifying when the certificate expires." >&2
      exit 1
      ;;
  esac
fi

echo "==> Designated requirement (stable across builds when signed by certificate)"
DESIGNATED_REQUIREMENT=$(codesign -d -r- "$APP_PATH" 2>&1 | grep designated || true)
echo "$DESIGNATED_REQUIREMENT"
if [ "$SIGN_ID" != "-" ]; then
  case "$DESIGNATED_REQUIREMENT" in
    # `codesign` canonicalizes a ten-character Team ID as a bare token even
    # though the requirement source passed to it quotes the value.
    *'identifier "com.dropdrive.DropDrive"'*"certificate leaf[subject.OU] = $TEAM_ID"*) ;;
    *)
      echo "Refusing to package: the signed app does not carry the stable Team-ID requirement." >&2
      exit 1
      ;;
  esac
fi

echo "==> Verifying signature and entitlements"
codesign -dv "$APP_PATH" 2>&1 | grep -E "Signature|Authority"
codesign -d --entitlements - --xml "$APP_PATH"

echo "==> Verifying every shipped binary covers $TARGET_ARCHS"
# Every shipped binary has to cover what TARGET_ARCHS claims. The app's own
# slice comes from xcodebuild, but yt-dlp and ffmpeg are fetched rather than
# built, so a stale DropDrive/Tools from before an architecture change would
# otherwise be packaged without complaint.
for REQUIRED in $TARGET_ARCHS; do
  for BINARY in "$APP_PATH/Contents/MacOS/DropDrive" \
                "$APP_PATH/Contents/Resources/yt-dlp" \
                "$APP_PATH/Contents/Resources/ffmpeg" \
                "$APP_PATH/Contents/Resources/deno"; do
    [ -f "$BINARY" ] || continue
    BINARY_ARCHS=$(lipo -archs "$BINARY" 2>/dev/null || echo "unreadable")
    case " $BINARY_ARCHS " in
      *" $REQUIRED "*) ;;
      *)
        echo "Refusing to package: $(basename "$BINARY") is '$BINARY_ARCHS', missing '$REQUIRED'." >&2
        echo "Re-run scripts/fetch-video-tools.sh if a bundled tool is stale." >&2
        exit 1
        ;;
    esac
  done
done
for BINARY in "$APP_PATH/Contents/MacOS/DropDrive" "$APP_PATH/Contents/Resources/yt-dlp" "$APP_PATH/Contents/Resources/ffmpeg" "$APP_PATH/Contents/Resources/deno"; do
  [ -f "$BINARY" ] && printf "    %-12s %s\n" "$(basename "$BINARY")" "$(lipo -archs "$BINARY" 2>/dev/null)"
done

echo "==> Staging DMG contents"
cp -R "$APP_PATH" "$STAGING_DIR/DropDrive.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "packaging/dmg/วิธีเปิดครั้งแรก · First launch.html" "$STAGING_DIR/วิธีเปิดครั้งแรก · First launch.html"

echo "==> Creating writable DMG"
rm -f "$RW_DMG"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING_DIR" -ov -fs HFS+ -format UDRW "$RW_DMG"

echo "==> Mounting and composing Finder window"
MOUNT_OUTPUT=$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)
DEVICE=$(echo "$MOUNT_OUTPUT" | egrep '^/dev/' | sed 1q | awk '{print $1}')
MOUNT_POINT="/Volumes/$VOLUME_NAME"

mkdir -p "$MOUNT_POINT/.background"
cp packaging/dmg/background.png "$MOUNT_POINT/.background/background.png"

osascript <<EOF
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 200 + $WINDOW_WIDTH, 120 + $WINDOW_HEIGHT}
    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to file ".background:background.png"
    set position of item "DropDrive.app" of container window to {$APP_ICON_POS}
    set position of item "Applications" of container window to {$APPLICATIONS_ICON_POS}
    set position of item "วิธีเปิดครั้งแรก · First launch.html" of container window to {$NOTE_ICON_POS}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF

sync
hdiutil detach "$DEVICE"

echo "==> Converting to compressed read-only DMG"
rm -f "$FINAL_DMG"
hdiutil convert "$RW_DMG" -format UDZO -o "$FINAL_DMG"

echo "==> Cleaning up build scratch (DerivedData, staging, intermediate dmg)"
rm -rf "$BUILD_DIR"

echo "==> Done: $FINAL_DMG"

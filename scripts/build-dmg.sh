#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(grep -m1 'MARKETING_VERSION' DropDrive.xcodeproj/project.pbxproj | sed -E 's/.*= ([0-9.]+);/\1/')
BUILD_DIR="build-adhoc"
STAGING_DIR="$BUILD_DIR/staging"
RW_DMG="$BUILD_DIR/DropDrive-rw.dmg"
FINAL_DMG="dist/DropDrive-v${VERSION}-adhoc.dmg"
VOLUME_NAME="DropDrive"
WINDOW_WIDTH=560
WINDOW_HEIGHT=460
APP_ICON_POS="140, 180"
APPLICATIONS_ICON_POS="420, 180"
NOTE_ICON_POS="280, 330"

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
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
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
# Falls back to ad-hoc when no certificate is present, so a fresh checkout on
# another machine still builds.
SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -oE '"Apple Develop(ment|er ID Application)[^"]*"' | head -1 | tr -d '"')
if [ -n "$SIGN_ID" ]; then
  echo "==> Signing as: $SIGN_ID"
else
  SIGN_ID="-"
  echo "==> No signing certificate found; falling back to ad-hoc"
  echo "    (updates will re-prompt for the keychain password every time)"
fi

if [ -d "$APPEX_PATH" ]; then
  codesign --force --deep --sign "$SIGN_ID" \
    --entitlements DropDriveShare/DropDriveShare.entitlements \
    "$APPEX_PATH"
fi
codesign --force --deep --sign "$SIGN_ID" \
  --entitlements packaging/DropDrive-adhoc.entitlements \
  "$APP_PATH"

echo "==> Designated requirement (stable across builds when signed by certificate)"
codesign -d -r- "$APP_PATH" 2>&1 | grep designated || true

echo "==> Verifying signature and entitlements"
codesign -dv "$APP_PATH" 2>&1 | grep -E "Signature|Authority"
codesign -d --entitlements - --xml "$APP_PATH"

echo "==> Verifying the binary is universal (Intel + Apple Silicon)"
ARCHS_BUILT=$(lipo -archs "$APP_PATH/Contents/MacOS/DropDrive")
echo "    architectures: $ARCHS_BUILT"
case "$ARCHS_BUILT" in
  *arm64*x86_64*|*x86_64*arm64*) ;;
  *)
    echo "Refusing to package: expected a universal binary, got '$ARCHS_BUILT'." >&2
    echo "An Apple-Silicon-only build cannot launch on an Intel Mac." >&2
    exit 1
    ;;
esac

echo "==> Staging DMG contents"
cp -R "$APP_PATH" "$STAGING_DIR/DropDrive.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "packaging/dmg/If DropDrive won't open.html" "$STAGING_DIR/If DropDrive won't open.html"

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
    set position of item "If DropDrive won't open.html" of container window to {$NOTE_ICON_POS}
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

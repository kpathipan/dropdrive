#!/bin/bash
# Sign a locally built app; does not install, quit, tag, push or publish.
set -euo pipefail
cd "$(dirname "$0")/.."
automation_app="build/automation-local/Build/Products/Release/DropDrive.app"
automation_identity='9070EAC8A2389F1B1CB486FA407411164BEDFC3A'
test -d "$automation_app"
security find-identity -v -p codesigning | grep "$automation_identity" >/dev/null
/usr/libexec/PlistBuddy -c 'Set :DDLocalAutomationBuild true' "$automation_app/Contents/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c 'Add :DDLocalAutomationBuild bool true' "$automation_app/Contents/Info.plist"
for tool in ffmpeg yt-dlp deno; do
  codesign --force --sign "$automation_identity" --timestamp "$automation_app/Contents/Resources/$tool"
done
codesign --force --deep --sign "$automation_identity" --timestamp --options runtime \
  --entitlements DropDriveShare/DropDriveShare.entitlements "$automation_app/Contents/PlugIns/DropDriveShare.appex"
codesign --force --sign "$automation_identity" --timestamp --options runtime \
  '-r=designated => identifier "com.dropdrive.DropDrive" and anchor apple generic and certificate leaf[subject.OU] = "YM8Y88VSBF"' \
  --entitlements packaging/DropDrive-adhoc.entitlements "$automation_app"
codesign --verify --deep --strict "$automation_app"
codesign -d -r- "$automation_app"

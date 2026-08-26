#!/bin/bash
set -euo pipefail

DMG="${1:-}"
PROFILE="${DROPDRIVE_NOTARY_PROFILE:-}"

if [ -z "$DMG" ] || [ ! -f "$DMG" ]; then
  echo "usage: DROPDRIVE_NOTARY_PROFILE=<notarytool-profile> $0 <dmg>" >&2
  exit 1
fi
if [ -z "$PROFILE" ]; then
  echo "Refusing to publish an unnotarized Developer ID build." >&2
  echo "Set DROPDRIVE_NOTARY_PROFILE to a profile created with xcrun notarytool store-credentials." >&2
  exit 1
fi
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q 'Developer ID Application'; then
  echo "Notarization requires a Developer ID Application certificate." >&2
  exit 1
fi

echo "==> Submitting $(basename "$DMG") to Apple notarization"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG"
echo "==> Notarization ticket stapled and validated"

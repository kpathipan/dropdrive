# DropDrive for Safari

A Safari Web Extension wrapping the same extension source as the Chrome version
(`browser-extension/chrome/manifest.json` and `background.js` — this project
references those files directly, so both browsers stay in sync automatically).

Generated with `xcrun safari-web-extension-converter`, Apple's supported tool for
turning a web extension into a distributable macOS app + Safari extension pair.
Ships as its own small companion app (as all Safari Web Extensions do — Safari
loads the extension from an installed **app**, not a loose folder like Chrome's
Developer Mode), separate from DropDrive.app itself.

## Build & install

1. Open `DropDrive Safari Extension/DropDrive Safari Extension.xcodeproj` in Xcode.
2. Build and run the "DropDrive Safari Extension" scheme once, to install the
   companion app.
3. In Safari: **Settings → Extensions**, enable "DropDrive Safari Extension".
4. Right-click a Drive link/page → **Download with DropDrive**, same as the Chrome
   version.

DropDrive.app must already be installed — the extension hands links off via its
`dropdrive://` URL scheme, just like the Chrome extension and the Share Extension.

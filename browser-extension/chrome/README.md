# DropDrive for Chrome

Adds a "Download with DropDrive" option to Google Drive pages and links, so a file
or folder goes straight into DropDrive's queue without copy/pasting the link.

## Install (unpacked, not published to the Chrome Web Store)

1. Open `chrome://extensions`.
2. Turn on **Developer mode** (top right).
3. Click **Load unpacked** and select this `browser-extension/chrome` folder.

## Use

- Right-click a link to a Drive file/folder → **Download with DropDrive**.
- On a Drive file/folder page itself, right-click anywhere → **Download this Drive
  item with DropDrive**, or click the extension's toolbar icon.

DropDrive must already be installed. The extension hands the link off via
DropDrive's registered `dropdrive://` URL scheme, which launches or activates the
app — the browser may show a one-time "Open DropDrive.app?" confirmation.

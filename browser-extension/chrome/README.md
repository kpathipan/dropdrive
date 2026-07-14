# DropDrive for Chrome

An Internet-Download-Manager-style integration: select one or more files or
folders on [drive.google.com](https://drive.google.com), click the DropDrive
icon next to Drive's own Download button (or right-click → **DropDrive**),
and the selection goes straight into DropDrive's queue — no copy/paste.

## Install (unpacked, not published to the Chrome Web Store)

1. Open `chrome://extensions`.
2. Turn on **Developer mode** (top right).
3. Click **Load unpacked** and select this `browser-extension/chrome` folder.

## Use

- Select one or more files and/or folders in Google Drive (list or grid
  view). Drive's own toolbar shows a Download icon when something is
  selected — DropDrive's icon appears right next to it. Click it, or
  right-click the selection and choose **DropDrive** (appears directly
  below **Download**).
- A "✓ Sent to DropDrive" toast confirms the hand-off.
- Multiple selected items are sent in the order they appear in Drive's own
  list/grid and queued in that order.

DropDrive must already be installed. The extension hands the selection off
via DropDrive's registered `dropdrive://download?url=` URL scheme (repeated
once per selected item for a multi-selection), which launches or activates
the app — the browser may show a one-time "Open DropDrive.app?" confirmation.

## Notes on how the injection works

Google Drive's web app is a single-page app with an internal DOM that isn't
a published API and changes over time. The content script targets stable
accessibility signals (`data-tooltip`/`aria-label="Download"` for the
toolbar button, `role="menuitem"` text for the context menu, `data-id` +
`aria-selected` for selection state) rather than Drive's own generated CSS
class names, and re-syncs itself via a debounced `MutationObserver` as Drive
re-renders during navigation and selection changes. If a future Drive
redesign changes these signals, the injection may need updating.

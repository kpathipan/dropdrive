# DropDrive v5.4.1 Release Notes

A follow-up to v5.4.0: multi-file and folder selection are now also
verified live (not just the single-file case), and the Safari extension
has been dropped rather than fixed and re-verified as a second target.

## What changed

### Safari extension removed
Its Xcode project only ever referenced `background.js` and `manifest.json`
from the shared Chrome source — `content.js` (the toolbar-button and
context-menu injection logic that's the actual point of the extension) and
the icon images `manifest.json` points at were never wired in. Safari
never actually had a working "Download with DropDrive" button or menu
entry, only the inert message-handling half. Rather than fix and
re-verify a second browser target, DropDrive is Chrome-only going
forward — matching the scope this integration was always primarily built
and tested for.

## What was verified — for real this time

Continuing from v5.4.0's single-file test, against the same live account:
- Selecting multiple files (`Cmd`-click, 3 files) and clicking the Chrome
  toolbar button queued all three in DropDrive, in selection order, as
  separate queue items.
- Selecting a folder and clicking the toolbar button analyzed and queued
  it as a single folder entry with its own file count and size.
- The right-click "DropDrive" context-menu entry confirmed directly under
  Drive's own "Download" item on a real file (not just reasoned about from
  the fix that landed it there).

## What still isn't verified

- A mixed selection (files and folders together) wasn't specifically
  tested — only an all-files and an all-folder selection were.
- Multiple concurrent large downloads (queue processing more than one
  large file back to back) wasn't watched end to end this round; v5.4.0's
  test was a single 1.95 GB file.

## Upgrading

Download `DropDrive-v5.4.1.dmg`, open it, and drag DropDrive.app to
Applications, replacing the previous version. For the extension: reload it
from `chrome://extensions` (unpacked, not on the Chrome Web Store), then
refresh any open drive.google.com tabs. If you'd previously installed the
Safari extension's companion app, you can delete it — it's no longer
maintained or referenced by this project.

## Known limitations

- Everything above in "What still isn't verified."
- Still signed with a local Apple Development certificate, not
  notarized — same standing limitation since 4.0.0. Building from source
  needs an Apple ID added under Xcode's own Accounts settings before
  `-allowProvisioningUpdates` can register the building device
  automatically.
- Update checker inactive pending a public repository.

# DropDrive v5.9.0 Release Notes

Downloads got tougher and tidier: network drops retry themselves, the
menu bar icon shows live progress, pausing is one click, and cancelling
cleans up after itself.

## Auto-retry

A download interrupted by a flaky connection no longer just fails.
DropDrive waits 5 seconds and tries again — then 15, then 45 — before
giving up, and each attempt continues from resume data instead of
starting over. The card shows the countdown, and Cancel/Pause work
during the wait exactly as they do mid-download.

## Live progress in the menu bar

While anything is downloading, the tray icon turns into a progress ring
you can watch without opening the popover. When the queue finishes, it
flashes a checkmark for a couple of seconds; if something failed, a
warning triangle stays until you deal with it. All template-drawn, so it
looks right in light and dark menu bars.

## Pause and resume, per item

The downloading card now has a Pause button next to Cancel, and a paused
row shows a blue Resume pill. Same engine as before (resume data is kept
whenever the server allows it) — just no longer buried in the footer.

## Clean cancels

Cancelling a folder download used to leave a half-filled folder on disk.
Now cancelling — or removing an unfinished item with ✕ — deletes what
was already downloaded. Safety: the app only deletes a folder still
carrying its own `.dropdrive-inprogress` marker, so a finished download
or a folder you created yourself can never be touched.

## First-run welcome

New installs see a one-time, three-step walkthrough: the app lives in
the menu bar (no Dock icon), paste a Drive link, pick a folder once.

## Upgrading

Quit the old version (menu bar icon → power button), open the DMG, drag
DropDrive.app to Applications, Replace. First launch may need
right-click → Open once.

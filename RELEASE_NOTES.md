# DropDrive v5.1.0 Release Notes

Chrome integration for the "download without copy/paste" workflow that v4.0.0
introduced for Chrome and Safari, plus a real bug in the Chrome extension that
would have kept it from working at all, plus a Menu Bar Mode that now actually
reflects what the app is doing.

## What's new / fixed

### Chrome, for real this time
The Chrome extension shipped in v4.0.0 (and touched again ahead of this
release) had a JavaScript bug that crashed its content script before it ever
ran: a `class` was referenced before its declaration, which — unlike a
`function` — isn't hoisted, so it threw immediately and the "Send to
DropDrive" button never got injected into Google Drive. Fixed, along with:
- The right-click context menu could appear on any website, not just Google
  Drive (missing `documentUrlPatterns`).
- An unused `scripting` permission and a manifest reference to icon files
  that don't exist — both surface as load warnings in `chrome://extensions`.
- Duplicated deep-link-building logic between the content script and the
  background worker, now consolidated into one place (the background
  worker, since only it can call `chrome.tabs.update`).

### Menu Bar Mode
The menu bar extra now shows the live download queue, active progress, and
Pause/Resume/Cancel — and it's the *same* state as the main window, not a
second independent copy that silently drifted out of sync (which is what it
was doing before this release).

### Deep link consistency
Every integration — Chrome extension, Safari extension, Share Extension —
now emits `dropdrive://download?url=<link>` consistently. The app's handler
was already written to accept any `dropdrive://<host>?url=` form, so this is
a producer-side cleanup, not a behavior change for anyone already using it.

### Notifications
Download-complete notifications now offer "Open DropDrive" alongside
"Reveal in Finder."

## Upgrading

Download `DropDrive-v5.1.0.dmg`, open it, and drag DropDrive.app to
Applications, replacing the previous version. Everything you had — sign-in,
history, preferences, destination folder, queue — carries over.

To use the Chrome integration: load `browser-extension/chrome` unpacked via
`chrome://extensions` → Developer Mode → Load unpacked (not published to the
Chrome Web Store). See [browser-extension/chrome/README.md](browser-extension/chrome/README.md).

## Known limitations in this release

- The Chrome extension fixes were verified by code review, JS/JSON
  validation, and an end-to-end test of the `dropdrive://download` link
  handler on the DropDrive side (confirmed the app launches, parses the
  link, and starts analysis) — not by an interactive click-through inside
  Chrome itself, since that access wasn't granted in this session. Worth a
  real click-through in Chrome before wide distribution.
- Edge/Brave/Arc are not implemented — out of scope for this release by
  design (Chrome only).
- Everything listed in v4.0.0's known limitations still applies
  (`GoogleAPIKey` unset, update checker inactive pending a real repo, not
  notarized).

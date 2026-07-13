# DropDrive v2.1.1 Release Notes

This release closes out the v2.1 line with a final audit pass and one real
bug fix, on top of everything shipped in v2.1.0.

## What's new since v2.1.0

- **Fixed:** dragging a link onto DropDrive's window could fail to pick up
  the link in some cases (when the dragged item offered both a URL and
  plain-text representation, and the URL one wasn't the actual Drive link).
  Drag-and-drop now tries both and uses whichever one is a valid Drive link.
- Added `PRIVACY.md`, documenting exactly what DropDrive does and doesn't
  do with your data.

## Everything in the v2.1 line (since v2.0.1)

- Recent Downloads: right-click any entry for **Reveal in Finder** or
  **Copy Google Drive Link**; **Clear History**; history now persists
  across launches
- **Drag and drop** a Google Drive link onto the window
- **Preferences** (`⌘,`): default download folder, open Finder on
  completion, notification sound, launch at login
- Native **menu bar item**: Open DropDrive, Recent Downloads, Preferences,
  Quit
- Optional **GitHub update check** — notification-only, never downloads or
  installs anything, and does nothing until a repository is configured

## Upgrading

Download `DropDrive-v2.1.1.dmg`, open it, and drag DropDrive.app to
Applications, replacing the previous version. Your Google sign-in,
download history, destination folder, and preferences all carry over —
nothing is reset by upgrading.

## Known limitations in this release

- `GoogleAPIKey` isn't configured, so anonymous access to public
  files/folders always falls back to signing in with Google. Downloads
  still work correctly either way.
- The GitHub update checker and the About panel's GitHub link are both
  inactive until a real repository is set (intentionally left as a
  placeholder rather than a fake link).
- `LICENSE` is a placeholder ("All Rights Reserved") pending a real
  licensing decision.
- Signed with a personal Apple Development certificate, not notarized —
  fine for direct or team distribution; wider public distribution would
  need a Developer ID certificate and notarization.
- If Google sign-in fails or is cancelled, the Connect button simply
  becomes available again with no error message shown. This is a known,
  pre-existing gap, not something newly introduced.

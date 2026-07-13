# Privacy

DropDrive is a local macOS app. This document describes exactly what it
does and doesn't do with your data, based on what's actually in the code —
not a generic privacy policy template.

## What DropDrive sends over the network

- **Google Drive API / Google Sign-In** (`googleapis.com`) — used to sign
  you in and to read metadata and file contents for links you paste. Only
  the `drive.readonly` OAuth scope is requested; DropDrive cannot modify,
  delete, or upload anything to your Drive.
- **GitHub Releases API** (`api.github.com`) — optional. DropDrive can
  check for a newer release and show a local notification if one exists.
  It never downloads or installs anything automatically. This feature is
  currently inert (no repository is configured in this build).

DropDrive has no analytics, telemetry, or crash-reporting SDKs, and no
backend server of its own. Downloaded file contents go directly from
Google's servers to the folder you choose — they never pass through any
DropDrive-operated infrastructure, because none exists.

## What's stored on your Mac

All of the following stays local, in this app's own sandboxed storage
(`UserDefaults` and Keychain) — none of it is transmitted anywhere except
where noted above:

- Your Google account's name, email, and profile image URL (for display in
  the toolbar), and your OAuth token (managed by Google's Sign-In SDK, kept
  in the Keychain)
- Your last-used and default download folders, as security-scoped
  bookmarks (so DropDrive can keep write access after you restart it)
- Recent download history: file/folder names, timestamps, status, and the
  Drive links you downloaded — not file contents
- Your Preferences toggles (open Finder on completion, play a sound,
  launch at login)

## Your controls

- **Disconnect** (toolbar account menu) revokes DropDrive's local session
  and clears cached Drive access. To fully revoke access from Google's
  side, use "Manage Connection" in the same menu.
- **Clear History** (Recent Downloads) deletes the local download history
  list. It does not delete the downloaded files themselves.
- Preferences can be reset by turning off the relevant toggle at any time.

## App Sandbox

DropDrive runs inside the macOS App Sandbox and can only read/write files
in folders you explicitly choose via the system file picker — it has no
broad filesystem access.

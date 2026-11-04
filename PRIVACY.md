# Privacy

DropDrive is a local macOS app with no advertising, analytics, telemetry,
crash-reporting SDK, or DropDrive-operated backend. This document reflects the
current application rather than a generic policy template.

## Network connections

DropDrive connects only when needed for features you use:

- **Google Drive and Google Sign-In** — reads metadata and file contents for
  Drive links. Download sign-in uses the read-only Drive scope. Mac uploads
  explicitly add `drive.file` when enabled by the user, allowing creation of
  selected files/folders without requesting full-Drive write access. Files are
  sent directly to Google; uploads do not change sharing or silently overwrite.
- **TikTok, YouTube, Facebook, and Instagram** — reads public metadata,
  thumbnails, and media for links you submit. Media travels directly from the
  platform or its content-delivery network to your chosen folder.
- **GitHub Releases** — checks for DropDrive updates. An update is downloaded
  and installed only after you press the update button; its checksum,
  architecture, and code signature are verified before replacement.
- **iCloud Drive phone inbox** — when enabled, macOS syncs small link files from
  the DropDrive folder in your iCloud Drive. DropDrive itself does not operate
  an iCloud server.

Downloaded content never passes through DropDrive-operated infrastructure,
because no such infrastructure exists.

## Data stored on your Mac

DropDrive stores only what is needed to keep the app useful between launches:

- Google account display details and an OAuth session managed by Google Sign-In;
  the credential is kept in macOS Keychain.
- Destination folders as security-scoped bookmarks, plus download, appearance,
  bandwidth, notification, phone inbox, and launch-at-login preferences.
- The pending queue, the 50 most recent history rows, bounded duplicate
  identifiers and lifetime totals, and bounded folder/collection fingerprints
  used to mark downloaded, new, or changed items. It does not retain a second
  copy of downloaded media.
- Small temporary resume, analysis, thumbnail, and tool-cache data. Completed
  or abandoned temporary data is removed automatically.
- Private upload checkpoints containing the original request, source identity,
  generated Drive file ID, accepted bytes and resumable session URL. These use
  app-private 0700/0600 storage outside the Automation IPC spool. Session URLs
  and Google tokens never appear in MCP results or logs. Checkpoints persist
  across cancellation/restart to prevent duplicate cloud files and are not
  automatically deleted on timeout. UI-picked sources retain local bookmarks.

## Your controls

- **Disconnect** clears the saved local Google session. **Manage Connection**
  opens Google's controls when you want to revoke access on Google's side.
- **Clear History** removes visible history, lifetime totals, duplicate memory,
  and folder/collection download markers. It never deletes downloaded files.
- Preferences can be changed or disabled at any time in the menu-bar Settings.

## App Sandbox

Sandboxed development configurations are limited to user-selected resources.
The existing stable-certificate DMG signing route runs the main app outside the
App Sandbox for file-based Keychain continuity; the Share extension remains
sandboxed. macOS file permissions and privacy controls still apply. MCP uploads
accept an explicitly supplied absolute regular-file path readable by that app;
they do not restrict sources to a particular working folder or follow symlinks.

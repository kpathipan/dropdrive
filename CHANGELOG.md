# Changelog

All notable changes to DropDrive are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

## [5.2.0] - Production readiness

### Fixed
- Cancelling or pausing a large file mid-download while it was using the
  multi-threaded ranged path silently ignored the cancellation and started
  a brand-new single-stream download instead of stopping — the error
  handling didn't distinguish "the user stopped this" from "one part had a
  transient failure," since both surface the same error type. Now checks
  actual task-cancellation state instead of inferring it from the error.
- Menu Bar Mode's popover rendered far narrower than designed, breaking
  the action-button row layout (buttons wrapped instead of sitting side by
  side). `MenuBarExtra` needs `.menuBarExtraStyle(.window)` for custom
  SwiftUI layouts — without it, rich content gets squeezed into a
  traditional-menu sizing model it wasn't designed for.
- "Open Window" in the menu bar could spawn a duplicate main window
  instead of focusing the existing one. The actual cause wasn't the
  button's own logic (which was already correctly guarding against it) —
  activating the app was triggering AppKit's default window-reopen
  handling independently. Fixed with an `NSApplicationDelegate` that makes
  reopen a no-op whenever a window already exists.
- Menu Bar Mode showed the raw Drive URL instead of the file/folder name
  for the active download and queue rows (main window already showed the
  name; this was a menu-bar-only regression from the same v5.1 change).
- Added accessibility labels to several icon-only buttons in Menu Bar Mode
  (quit, preferences, reveal/retry/remove) that had a tooltip but no
  VoiceOver label.

### Verified (no code change)
- Zero leaks and stable idle CPU/memory across repeated menu bar
  open/close cycles.
- Debug and Release builds clean with zero app-code warnings; Safari
  extension project rebuilds clean (no Safari-specific changes this
  release, per scope — Chrome remains the only browser worked on).

## [5.1.0] - Chrome integration

### Added
- Menu Bar Mode: the menu bar extra now shows live queue/progress, with
  Pause/Resume/Cancel on the active download and per-item actions, sharing
  the same live state as the main window (previously each held its own
  independent, out-of-sync copy)
- Download-complete notifications gained an "Open DropDrive" action
  alongside "Reveal in Finder"

### Fixed
- Chrome extension: the injected "Send to DropDrive" button never worked —
  `content.js` referenced a `class` before its declaration, which throws
  and aborts the whole script in JavaScript (no hoisting for classes the
  way there is for functions)
- Chrome extension: the "Send to DropDrive" context menu could appear on
  any website, not just Google Drive, because the page-context menu item
  only had `targetUrlPatterns` (which constrains link/image targets) and
  no `documentUrlPatterns` (which constrains the page itself)
- Chrome extension: removed an unused `scripting` permission and a
  manifest `icons` block pointing at image files that don't exist (both
  would surface as load-time warnings/errors in `chrome://extensions`)
- Removed a second, unwired deep-link handler and environment key in
  `DropDriveApp.swift` that duplicated (and could have silently diverged
  from) the one actually in use
- Removed a forked, drifted copy of the browser-extension JS that had
  been placed inside the Safari extension's app folder; the Xcode project
  was never pointed at it, so it was dead weight, and Safari continues to
  reference the single Chrome source of truth directly

### Changed
- The `dropdrive://` deep link host is now consistently `download`
  (`dropdrive://download?url=...`) everywhere it's emitted — Chrome
  extension, Safari extension, Share Extension. The app-side handler was
  already host-agnostic, so this is a producer-side consistency fix, not
  a breaking change.
- Chrome/Safari extension messaging simplified: the content script asks
  the background service worker to open DropDrive (`chrome.tabs.update`
  isn't available to a content script); nothing else builds or sends the
  deep link independently anymore.

## [4.0.0] - Productivity sprint

### Added
- Resumable downloads (app quit, network drop, or explicit pause), with
  graceful fallback to a fresh restart when resume isn't possible
- Optional bandwidth limit (Unlimited / 5 / 10 / 20 MB/s / Custom)
- Multi-threaded ranged downloads for large files when the server supports it
- Smart destination naming — collisions get `(1)`, `(2)`, … instead of being
  overwritten
- Pause/Resume for the whole download queue
- Drag-and-drop reordering of pending queue items
- Duplicate-download detection now also checks Recent Downloads across past
  sessions, not just the current one
- Search Recent Downloads by name
- Lightweight local download statistics (total downloads/files/size) in
  Preferences — no analytics, no telemetry
- Chrome extension, Safari extension, and a native Share Extension, all
  sending links into DropDrive via a new `dropdrive://` URL scheme
- `.fileURL` (e.g. dragged `.webloc` files) added to drag-and-drop support,
  alongside the existing URL/plain-text handling

### Fixed
- Google Drive "shortcut" items (added via *Add shortcut to Drive*) failed
  to download; they're now resolved to their real target transparently
- Links carrying a Drive `resourcekey` parameter previously 404'd; the key
  is now parsed and sent with every request for that item

### Changed
- The download-complete notification's action is now labeled "Reveal in
  Finder" (previously "Open Folder"); behavior was already reveal-in-Finder

## [2.1.1] - Final release sprint

### Fixed
- Drag-and-drop now correctly falls back to a dropped item's plain-text
  representation when its URL representation doesn't parse as a Drive
  link, instead of giving up (a provider can offer both, and the URL one
  isn't always the useful one)

### Added
- PRIVACY.md — a concrete description of what DropDrive does and doesn't
  do with your data
- RELEASE_NOTES.md for this release

### Verified
- Full project audit: no dead code, no duplicate logic, no unused assets,
  no TODO/FIXME/HACK markers, zero warnings in Debug and Release
- All documented user flows reviewed against source: public/private
  file/folder downloads, invalid/deleted links, OAuth, cancel/retry,
  progress, Recent Downloads, drag-and-drop, Preferences, menu bar, About
  panel, accessibility, keyboard navigation, Dark/Light Mode

## [2.1.0] - Production polish sprint

### Added
- "Reveal in Finder" and "Copy Google Drive Link" on every Recent Downloads entry (right-click)
- "Clear History" for Recent Downloads
- Recent download history now persists across launches
- Drag-and-drop of Google Drive links onto the main window
- Preferences window: default download folder, open Finder on completion, notification sound, launch at login
- Native menu bar item (Open DropDrive, Recent Downloads, Preferences, Quit)
- Optional GitHub Releases update checker (notify-only; never auto-downloads or auto-installs)
- Production repo assets: README, CHANGELOG, LICENSE, CONTRIBUTING, issue/PR templates

### Fixed
- Single-file download completion message no longer reads as "saved to" the file itself
- About panel no longer shows the build number twice
- About panel version string is now read from the bundle instead of being hardcoded

### Changed
- Recent download history moved from in-memory view state into a persisted, shared store

## [2.0.1]

### Fixed
- Removed dead code: unused `GoogleSignInSwift` package dependency, unused `DropDriveViewModel` state, unused `DownloadRequest` field
- Card and input field backgrounds now render correctly in both Light and Dark Mode (previously assumed Dark Mode only)
- Recent Downloads status icons now have VoiceOver labels

## [2.0.0-Dev] - Smart Link Analysis

### Added
- Smart Link Analysis: paste-to-preview before downloading, with public/private detection and file/folder support
- Destination folder memory and window frame persistence across launches
- Native completion notifications
- Sanitized, user-friendly error messages
- Invalid-link detection with inline feedback
- Paste/Clear affordances, Return-to-confirm, Escape-to-cancel

## [1.0.0-beta] - Initial release

### Added
- Google Sign-In and Drive API access (including Shared Drives)
- Folder and file downloads, with Google Docs/Sheets/Slides export support
- Real-time progress (bytes, speed, ETA) with cancel support
- Native macOS UI with light/dark appearance support

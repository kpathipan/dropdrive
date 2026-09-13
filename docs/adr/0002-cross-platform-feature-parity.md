# ADR-0002: Cross-platform feature parity

**Status:** Accepted
**Date:** 2026-09-13

## Context

The first Windows builds implemented a downloader-shaped prototype rather than
DropDrive itself. Keeping two unrelated feature implementations would make the
Windows app permanently lag behind macOS and would repeat download, queue, and
update bugs independently.

## Decision

Treat the macOS behavior and visual tokens as the product contract. Windows may
use native Windows integrations and a normal compact window, but it must expose
the same user workflows:

- Analyze before download, including duplicates and disk-space preflight.
- Public/private Google Drive files and folders with multiple accounts.
- Folder item cards/list, select-all semantics, thumbnails, and preview.
- YouTube, TikTok, Instagram, and Facebook media; MP3, quality, subtitles,
  trimming, chapters, artwork, playlists, and carousels where available.
- A persistent per-destination queue with pause, resume, retry, reordering, and
  recoverable attention states.
- Persistent recent downloads with open, reveal, copy-link, retry, and search.
- Completion/attention notifications, bandwidth control, launch at login,
  compatible-video preference, language, theme, and a 24-hour update cadence.

Platform-specific entry points are adapted rather than copied: the macOS menu
bar popover becomes a compact Windows window and notification-area icon; Finder,
Quick Look, Keychain, Login Items, and iCloud inbox map to Explorer, Windows
preview, Credential Locker/DPAPI, Startup Apps, and an optional OneDrive inbox.

## Consequences

- Feature work starts from shared behavioral tests and parity fixtures.
- A Windows release is built on a Windows CI runner and must pass unit, XAML,
  packaging, and installed-app smoke tests before its update feed is published.
- Google OAuth requires a Windows Desktop client ID. Client IDs may ship in the
  app; refresh tokens must only be stored with Windows data protection.
- Automatic checks run at most once per 24 hours. Manual checks bypass the gate.

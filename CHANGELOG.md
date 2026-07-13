# Changelog

All notable changes to DropDrive are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

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

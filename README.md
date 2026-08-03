# DropDrive

DropDrive is a native macOS app that downloads Google Drive files and folders directly to your Mac — paste a link, review what it points to, and download it.

## Features

- **Smart Link Analysis** — paste a Drive link and see what it is (file or folder, size, file count, owner, public/private) before downloading anything, including items behind a Drive "shortcut" or a `resourcekey`-protected link
- **Video downloads** — paste a TikTok / YouTube / Facebook / Instagram link instead and DropDrive downloads the video through bundled yt-dlp + ffmpeg (TikTok without the watermark, YouTube at full quality), with the same queue, progress, and history
- Public links download without signing in; private links prompt for Google sign-in only when actually needed
- Real progress reporting (bytes, speed, ETA) with cancel support; downloads **resume** after an interruption whenever the server allows it, and large files can download over **multiple concurrent connections**
- Optional **bandwidth limit**, and a queue that can be **paused/resumed** and **reordered** by drag-and-drop
- Destination collisions get a smart `(1)`, `(2)`… suffix instead of being overwritten
- Recent download history, persisted across launches and **searchable**, with **Reveal in Finder** and **Copy Google Drive Link** on every entry, plus lightweight local download statistics in Preferences
- Duplicate-download detection across sessions, not just the current one
- Drag and drop a Drive link straight onto the window (from a browser, as text, or as a dragged URL file)
- Send a link into DropDrive without copy/paste: a [Chrome extension](browser-extension/chrome), or the macOS **Share menu**
- Native notifications on completion, with **Reveal in Finder** and **Open DropDrive** actions
- **Menu-bar-only app** — no Dock icon, no separate window; the whole app opens in a popover under its menu bar icon, with an icon rail switching between Queue, Recent, Statistics, and Preferences
- Preferences for default download folder, auto-open in Finder, notification sound, launch at login, and bandwidth limit
- Optional GitHub-based update check (notify-only — DropDrive never auto-downloads or auto-installs updates)

## Requirements

- macOS 14 or later, on an Apple Silicon Mac (M1 or newer)
- A Google account (only required for private files/folders)

## Installing

Download the latest DMG from the project's Releases, open it, and drag
DropDrive.app to Applications. See [CHANGELOG.md](CHANGELOG.md) for what's
in each version.

## Building

1. Open `DropDrive.xcodeproj` in Xcode.
2. Set your own Development Team under the target's Signing & Capabilities.
3. Fill in `DropDrive/Info.plist`:
   - `GIDClientID` / `REVERSED_CLIENT_ID` — from a Google Cloud OAuth client for macOS.
   - `GoogleAPIKey` — optional; enables anonymous access to public files/folders without sign-in. Leave the placeholder as-is to disable this and always use OAuth.
4. Build and run.

## Architecture

- SwiftUI, MVVM, `@Observable` view models (macOS 14 Observation framework)
- `Services/` — Google Sign-In, Drive API access, downloading, notifications, preferences, update checking
- `ViewModels/` — `DropDriveViewModel` drives the main window's state machine
- `Views/` — SwiftUI views, kept presentation-only

## Privacy

See [PRIVACY.md](PRIVACY.md) for what DropDrive does and doesn't do with
your data.

## License

See [LICENSE](LICENSE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

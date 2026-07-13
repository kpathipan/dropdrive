# DropDrive v4.0.0 Release Notes

A productivity-focused sprint on top of v3.1.0: a more reliable download engine
(resumable, throttleable, multi-threaded, shortcut/resourceKey-aware), a
more capable queue (pause/resume, drag-to-reorder, smart naming, duplicate
detection across sessions), search and lightweight local stats for Recent
Downloads, and three new ways to send a Drive link into DropDrive without
copy/paste: a Chrome extension, a Safari extension, and a native macOS Share
Extension.

## What's new

### Download engine
- **Fixed** a class of Drive items that previously failed outright: Drive
  "shortcuts" (an item added via *Add shortcut to Drive*) are now resolved
  to their real target transparently, and links carrying a `resourcekey`
  parameter (Google's newer sharing-security parameter, required for some
  older/rekeyed shared items) are now honored instead of silently 404ing.
- **Resumable downloads**: an interrupted download (app quit, network drop,
  explicit pause) resumes from where it left off whenever the server
  supports it, and falls back to a clean restart otherwise. Already-completed
  files in a folder download are skipped on resume rather than redownloaded.
- **Bandwidth limit**: optional download speed cap in Preferences
  (Unlimited / 5 / 10 / 20 MB/s / Custom).
- **Multi-threaded downloads**: large files are automatically split into
  concurrent ranged requests when the server supports it, with a safe
  fallback to a single stream when it doesn't.
- **Smart naming**: a download that would collide with an existing file or
  folder is automatically suffixed `(1)`, `(2)`, … instead of overwriting it.

### Queue
- **Pause/Resume** the whole queue; the active download stops safely and
  picks back up (or restarts, if resume isn't possible) when resumed.
- **Drag to reorder** pending items in the queue.
- **Duplicate detection** now also checks Recent Downloads (not just the
  current session), and asks before re-downloading something you already have.

### Recent Downloads
- **Search** by file/folder name.
- **Reveal in Finder** is now the consistent label everywhere (including the
  completion notification, which previously said "Open Folder" — same
  behavior, clearer name).
- **Statistics** (in Preferences): total downloads, total files, total size —
  computed locally from your own history, nothing leaves your Mac.

### Send a link without copy/paste
- **Chrome extension** (`browser-extension/chrome`): right-click a Drive
  link or page → *Download with DropDrive*. Load unpacked; not published to
  the Chrome Web Store.
- **Safari extension** (`browser-extension/safari`): same capability,
  packaged as its own small companion app per Safari's extension model.
- **Share Extension**: send a Drive link to DropDrive from any app's Share
  menu.
- All three hand off through a new `dropdrive://` URL scheme — no native
  messaging host, no App Group, just DropDrive being asked to open a link.

## Upgrading

Download `DropDrive-v4.0.0.dmg`, open it, and drag DropDrive.app to
Applications, replacing the previous version. Everything you had — sign-in,
history, preferences, destination folder — carries over.

## Known limitations in this release

- Live regression testing against real Drive files (every file type, both
  extensions, the Share Extension) needs a signed-in Google account and real
  Drive links; this was verified as far as possible in a sandboxed build
  environment (clean Debug/Release builds, structural UI checks, code
  review) but a full click-through with real files is still worth doing
  before wide distribution.
- Multi-threaded downloads don't carry resume data if interrupted — they
  fall back to a fresh single-stream restart, which is still correct, just
  not byte-resumed.
- The Chrome and Safari extensions aren't published to their respective
  stores; both are load-locally/build-locally deliverables.
- `GoogleAPIKey` isn't configured, so anonymous access to public
  files/folders always falls back to signing in with Google.
- The GitHub update checker and the About panel's GitHub link remain
  inactive until a real repository is configured (unchanged from v3.1.0).
- Signed with a personal Apple Development certificate, not notarized —
  fine for direct or team distribution; wider public distribution would
  need a Developer ID certificate and notarization.

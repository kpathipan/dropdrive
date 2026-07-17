# Changelog

All notable changes to DropDrive are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

## [5.7.1] - Every queued file was sharing one destination

### Fixed
- **Pasting a second link while one was downloading sent it to the same
  folder as the first, no matter what "Save to" showed.** `QueueItem` had
  no destination of its own — `processQueueIfNeeded` read the view model's
  single `selectedDestinationURL` at the moment a download *started*, not
  when it was queued. Changing "Save to" while anything was still pending
  silently moved every queued item's destination, including files queued
  before the change. `QueueItem` now captures `destinationURL` at enqueue
  time; each item downloads to the folder that was selected when it was
  added, and changing "Save to" only affects links pasted after that.
- **"Connect" stayed up after a successful sign-in on a private file.**
  `signInWithGoogle()` retried the pending link by assigning it back to
  `driveLink`, relying on that property's `didSet` to re-trigger analysis.
  But the link never left the text field, so the assignment was a no-op,
  and `didSet` deliberately ignores no-op writes. Analysis never re-ran;
  only quitting and re-pasting worked, because that's a real change.
  `scheduleAnalysis()` is now called explicitly after sign-in.

### Changed
- **Folder downloads run several files at once instead of one at a time.**
  A folder of many small files spent most of its wall-clock time on
  per-file round-trip latency rather than transfer — paid once per file,
  serially. Up to 5 files now download concurrently (each still eligible
  for its own multi-part split past 20 MB), which should meaningfully
  speed up folders with many files. Progress now reflects whichever file
  most recently reported bytes rather than one strictly-ordered name, since
  several are in flight at once.
- **Removed the public/private lock-or-globe badge** from the queue rows
  and the duplicate-download prompt — every file the reporting user
  downloads is private, so it added nothing per-row. The "sign in to access
  this item" lock icon is unrelated and stays; it's the only thing telling
  the user *why* a Connect button appeared.
- **Removed the Chrome extension** (`browser-extension/`). Pasting a link
  directly, or using the macOS Share menu (`DropDriveShare.appex`, which
  hands off through the same `dropdrive://` URL scheme independently of
  the extension), remain.

## [5.7.0] - The DMG could never have run on an Intel Mac

Reported from the first real attempt to hand the app to someone else:
"can't open it, ran the Terminal command, nothing happened."

### Fixed
- **Every DMG so far was Apple-Silicon-only.** `xcodebuild` picks the first
  matching destination when given none, which on this machine is
  `arch:arm64` — so the shipped binary was `arm64` alone and could not
  launch on an Intel Mac at all, no matter how many times the quarantine
  command was run. `scripts/build-dmg.sh` now builds with
  `-destination 'generic/platform=macOS'` and explicit
  `ARCHS="arm64 x86_64"`, and refuses to package anything that isn't
  universal rather than shipping the same silent failure again. Verified:
  every Mach-O in the bundle, including the Share extension, is now
  `x86_64 arm64`.
- **The quarantine command didn't reach nested code.** The note said
  `xattr -d com.apple.quarantine …`, which only clears the bundle root; the
  app embeds a Share extension that carries its own quarantine flag. It's
  now `xattr -cr …` — recursive, and quiet when an attribute isn't present
  instead of printing errors at someone following instructions.

### Known limitation
The minimum is still macOS 14. `@Observable` (three files) and two-argument
`onChange` require it; dropping to 13 means converting those, and dropping
to 11 additionally costs `MenuBarExtra` and drag-to-reorder, which are
13-only.

## [5.6.1] - Controls that look clickable now are

### Fixed
- **The queue's ✕ did nothing.** A cancelled row drew an
  `xmark.circle.fill` status icon — the standard macOS remove glyph — but
  it was only ever an icon; Remove lived exclusively in the right-click
  menu. Every row that isn't mid-download now has a real remove button,
  and the cancelled status icon is `slash.circle` so it stops
  impersonating a control. Same class of bug as reveal-in-Finder being
  context-menu-only in 5.5.0.
- **The Chrome button died silently after an extension reload.** Reloading
  or updating the extension leaves the previously-injected content script
  running in open Drive tabs with a dead `chrome.runtime`, so clicking
  threw an uncaught "Extension context invalidated" — visible only on
  `chrome://extensions`, which just looked like a dead button. It now
  detects the stale context and shows "DropDrive was updated — reload this
  page to use it".
- **Toasts kept their first message.** `showToast()` only set its text when
  creating the element, so a reused toast showed whatever it said first.

### Changed
- The Chrome extension's manifest version tracks the app again (it sat at
  5.4.4 while the app moved through 5.4.5 → 5.6.0; it was simply never
  bumped alongside it).

### Verified
The remove button was exercised on a real queue row and removes as
expected. The reloaded extension injects its button into a Thai-locale
Drive and hands the selection off to the app.

### Not verified
The stale-extension toast. It only fires when a content script outlives an
extension reload, and the reload that would have triggered it was done
alongside a page refresh — the path it guards is still unobserved.

## [5.6.0] - Sign-in actually works on a free build

"It asks me to connect while already connected" was two separate faults
stacked on top of each other, and neither was in the app's logic.

### Fixed
- **Google sign-in could never complete.** GoogleSignIn stores its session
  in the *data-protection* keychain (it sets
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, which forces
  `kSecUseDataProtectionKeychain`). On macOS that keychain requires an
  `application-identifier` entitlement that only a real Apple Team
  signature provides, so an ad-hoc signed build failed every write with
  `errSecMissingEntitlement` (-34018); GID surfaced it as "keychain
  error" (-2) the instant the OAuth redirect succeeded, leaving
  `currentUser` nil forever. Confirmed with an ad-hoc test binary: -34018
  from the data-protection keychain, `errSecSuccess` from the file-based
  one. GID exposes no public way to swap its store, so `LoginManager` now
  drives **AppAuth + GTMAppAuth directly** — both already linked — and asks
  for `.useFileBasedKeychain`, which needs no entitlement. Verified live:
  sign-in completes, the session survives quit/relaunch *and* a rebuild
  with a fresh ad-hoc signature, and the Drive API authenticates.
- **The account chip claimed a session that wasn't there.**
  `restoreSavedAccount()` fell back to a UserDefaults-cached account even
  when no session could be restored, so the header showed "connected"
  while every private-file analysis still demanded sign-in. It now only
  reports an account when one genuinely restores, and clears the stale
  cache otherwise.

### Changed
- **The ad-hoc build is no longer sandboxed.** A sandboxed app can't reach
  the keychain at all without `keychain-access-groups`, which macOS only
  honours behind a real Team prefix; self-assigning one (with or without
  `com.apple.application-identifier`) makes launchd refuse to spawn the
  app. Re-signing with the sandbox back on reproduced the failure — the
  chip went empty because the stored session couldn't be read. Both
  changes are needed together. This build ships as a DMG rather than
  through the App Store, where the sandbox is optional; the Team-signed
  build keeps its sandbox, and the Share extension stays sandboxed.

### Note
Google Cloud's consent screen for this project was also switched from
Internal to External/in-production — while it was Internal, any account
outside the owning Workspace was rejected with `403 org_internal` before
the keychain ever came into play.

## [5.5.0] - New identity: icon, wordmark, and a tidier UI

A visual pass. New app icon everywhere, a proper logo-plus-wordmark
header, a main window that actually fits its content, a visible
reveal-in-Finder button, and a simplified menu bar.

### Added
- **New app icon** across every size (16→1024). The old generic tray
  glyph is replaced by a document-dropping-into-a-tray mark, extracted
  pixel-exact from the source render and masked to a transparent
  squircle.
- **Logo + two-color wordmark header.** The main window (and the menu
  bar) now show the app logo above "DropDrive" with `Drop` in the
  primary label color and `Drive` in blue. `Drop` uses `.primary` so it
  stays legible in both light and dark mode rather than a fixed dark hex.
- **Visible reveal button in Recent Downloads.** Revealing a finished
  download in Finder was previously buried in the right-click menu only.
  Each row with a file on disk now shows an always-visible folder button
  (accent on hover); the context menu still works too.

### Changed
- **Menu bar redesigned to a lighter layout.** Dropped the full queue
  list that made it feel like a second copy of the app. It now shows a
  paste-link field (submits and brings the window forward), a single
  status line (live progress with pause/cancel while downloading, or a
  short "N downloads today" / "Ready" summary when idle), and Open
  DropDrive / Preferences buttons.
- **Main window fits its content.** It previously opened ~900pt wide with
  the 360pt content stranded in the middle: `.frame(maxWidth:)` only
  bounds the view, and `.windowResizability(.automatic)` let the window
  ignore it. Now `.contentSize` makes the window hug the content's ideal
  frame, opening at a compact ~460×570.

### Packaging
- The ad-hoc DMG build is scripted (`scripts/build-dmg.sh`) with a
  composed Finder window (flat background, arrow, tight size) and bundles
  an in-DMG "If DropDrive won't open" note for the one-time
  `xattr -d com.apple.quarantine` step. The script cleans up its own
  build scratch so duplicate `.app` copies stop accumulating in Spotlight.

## [5.4.4] - Three real bugs found from live use, not testing

Reported directly from using the app, not found by QA: a redundant login
prompt despite already being signed in, a new hidden window piling up on
every Chrome deep link, and occasional corrupted downloads.

### Fixed
- **Redundant login prompt.** `cachedAccessTokenIfAvailable()` only checked
  `GIDSignIn.sharedInstance.currentUser`, which can still be `nil`
  immediately after launch — restoring a previous session happens
  asynchronously and separately (`restoreLogin()`, triggered from the
  UI). A deep link's analysis could race ahead of that restore and wrongly
  conclude "not signed in" even though a valid session existed. Now
  attempts the same silent restore itself instead of assuming another,
  unsynchronized call already finished first.
- **A new hidden window piling up, both on plain launch and on every Chrome
  deep link.** Confirmed by direct reproduction (not just reasoned about):
  a clean launch alone could produce 2+ main windows with zero user
  interaction, and each incoming `dropdrive://` link while already running
  added another. `.onOpenURL` was removed — incoming URLs now go through
  `NSApplicationDelegate.application(_:open:)` once, directly against the
  shared view model — but SwiftUI's `WindowGroup` still independently
  spawned extra window instances regardless, so this is enforced directly:
  the app delegate now sweeps for windows titled "DropDrive" (SwiftUI sets
  this synchronously and consistently, unlike `WindowAccessor`'s own
  `frameAutosaveName` tagging, which a live repro showed losing a race and
  silently missing 2 of 3 real duplicates) after launch, after every
  incoming URL, and whenever any window becomes main, closing every extra
  down to one.
- **Occasional corrupted downloads.** The multi-threaded ranged-download
  path probes once for `Range` header support before starting, but never
  re-checked that each of the 4 concurrent part-requests actually got back
  `206 Partial Content` rather than `200` with the *entire* file — some
  CDNs/caches honor `Range` inconsistently, especially once a URL is
  already cached. A `200` response for a "part" silently meant that part
  file held the whole file, and concatenating it with the other three
  produced a garbled, oversized result with no error at any point. Each
  part now requires exactly `206`; anything else fails that part and falls
  back to the existing reliable single-stream path instead of writing a
  corrupted file.

## [5.4.2] - Beta label

### Changed
- The status bar and About panel read "Dev" — a leftover from before this
  release had been verified against a real Chrome/Drive workflow. Now
  that it has (see 5.4.0/5.4.1), relabeled to "Beta".

## [5.4.1] - Chrome-only

### Removed
- Dropped the Safari extension entirely. Its Xcode project only ever
  referenced `background.js` and `manifest.json` from the shared Chrome
  source — `content.js` (the toolbar-button and context-menu injection
  logic that's the actual point of the extension) and the icon images
  `manifest.json` points at were never wired in, so Safari never actually
  had a working "Download with DropDrive" button or menu entry, only the
  inert message-handling half. Rather than fix and re-verify a second
  browser target, DropDrive is Chrome-only going forward, matching the
  scope this integration was always primarily built and tested for.

## [5.4.0] - Chrome integration verified end-to-end

### Fixed
- Chrome extension couldn't launch DropDrive at all in practice: none of the
  Chrome-side selector fixes from 5.3.0 had ever been checked against a real,
  live Drive session. Live testing this release found and fixed two real
  selector bugs (the selection toolbar's actual ARIA role is `region`, not
  `toolbar`; `data-tooltip`/`aria-label` values are localized, not just the
  visible text — confirmed against a Thai-locale account), a drag-and-drop
  return-value bug in the queue reorder handler, and a macOS 26.0-only
  `dropDestination` overload the compiler was silently picking over the
  macOS 13+ one available at this app's actual deployment target.
- Auth flow: opening a private file via the Chrome extension before signing
  in previously left the user stuck after login with no next step. The
  pending link is now stored and automatically retried once sign-in
  succeeds, with no need to re-select the file in Chrome.
- Chrome's own item context menu renders in two passes — a quick partial
  menu, then a fuller one moments later — and the second pass was
  reshuffling the DOM in a way that stranded the injected "DropDrive" entry
  at the top of the menu instead of directly under "Download". Injection is
  now re-entrant (re-checked on every later menu mutation, not just once)
  and anchors off the last matching "Download" node rather than the first.
- Lowered `MACOSX_DEPLOYMENT_TARGET` from the Xcode-default `26.5` down to
  `14.0`, the actual floor set by `@Observable`/`Observation` usage — this
  had never been revisited since project creation.

### Changed
- Chrome toolbar button redesigned: a small solid-blue pill (cloud-down
  glyph + "DropDrive" label) instead of a bare gray icon that read too
  close to Drive's own Download button. Sized off a two-layer box — an
  outer box matching the reference Download button's height for row
  alignment, an inner pill for the small visible chip — so it lines up with
  neighboring icons regardless of how Drive's own row aligns its children.

### Verified (real, live, end-to-end — not simulated)
This is the first release where the full Chrome → DropDrive workflow was
actually exercised against the live drive.google.com UI rather than reasoned
about from documented DOM conventions:
- Selecting a real private file and clicking the Chrome toolbar button sends
  it to DropDrive via `dropdrive://download?url=...`.
- The app receives the link, detects it needs Google sign-in, and — after
  signing in — automatically queues the file without any manual re-entry.
- A real 1.95 GB file downloaded to completion; the resulting file was
  verified on disk (correct size, valid, unstructured video data).
- "Reveal in Finder" opened Finder with the completed file selected.
- The right-click "DropDrive" entry appears directly under Drive's own
  "Download" item in the file context menu.

### Known gaps
- Multiple-file selection, folder selection, and the Safari extension were
  not re-verified this round (only a single private file was exercised
  through the full live flow above).
- Still signed with a local "Apple Development" certificate, not notarized
  — same standing limitation since 4.0.0. A machine building this needs an
  Apple ID added under Xcode's own Accounts settings for
  `-allowProvisioningUpdates` to register the device automatically;
  without one, the signed build fails outright with "No Accounts" rather
  than a signing error.

## [5.3.0] - Final Chrome integration sprint

### Changed
- Rewrote the Chrome extension's selection model. It previously only
  detected a Drive item from the page URL (`/file/.../` or `/folders/...`),
  which meant it did nothing on Drive's actual file-listing/selection UI —
  the primary way people use Drive. It now reads the real selection
  (`[aria-selected="true"][data-id]`), works in both List and Grid view,
  and supports single, multiple, folder, and mixed selections, sent to
  DropDrive in the order they appear in Drive's own list/grid.
- Toolbar integration: instead of an always-injected custom-styled button,
  DropDrive's icon is now inserted directly next to Drive's own Download
  button (matched primarily via `data-tooltip`/`aria-label="Download"`),
  sized to match, with a "Download with DropDrive" tooltip. It appears and
  disappears with Drive's own Download button rather than being always
  present.
- Context menu integration: previously only used `chrome.contextMenus`,
  which only affects the browser's native right-click menu — Google Drive
  renders its own custom right-click menu and suppresses the native one
  entirely, so that never actually appeared on a file/folder row. Now also
  detects Drive's own menu opening and inserts a "DropDrive" item directly
  below "Download" inside it, cloned from Drive's own item so it matches
  styling automatically.
- Added a "✓ Sent to DropDrive" toast on send, single-instance (re-sending
  resets its timer rather than stacking a second one).
- `dropdrive://download?url=` now accepts the `url` parameter repeated
  once per selected item (`?url=A&url=B`) for a multi-selection, still the
  one endpoint — not a new one. Minimal corresponding change on the
  DropDrive app side: multi-item deep links are analyzed and queued in
  order, silently (no per-item duplicate-redownload prompt interrupting a
  batch).
- Added real extension icons (16/48/128), derived from DropDrive's own app
  icon, replacing the missing-icon manifest gap.
- Simplified the MutationObserver-driven re-sync logic (the previous
  version's "is this mutation relevant" filtering was dead code — it always
  evaluated true — removed rather than fixed in place, since the
  requestAnimationFrame debounce already bounds the cost without it).

### Known limitation
- None of the Chrome-side changes in this release could be verified against
  the live drive.google.com DOM — interactive browser automation
  (Computer Use write access, Claude-in-Chrome) was unavailable this
  session. Selectors are layered/defensive and reasoned from documented
  Google Drive DOM conventions, but are unverified. See RELEASE_NOTES.md
  for what was and wasn't checked, including a concrete, observed risk
  (the account seen mid-session had Drive set to Thai, which may affect
  text-based matching).

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

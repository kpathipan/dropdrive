# DropDrive — Handoff

**Status as of this session:** v5.1.0 tagged, built, DMG in `dist/`, repo clean.

This supersedes `HANDOFF_v5.1_CHROME.md` and `RELEASE_NOTES_5.0.0.md` (now
removed) — those described a prior session's in-progress state, and some of
what they marked "DONE" (Chrome extension, the app-side deep-link handler)
had real bugs that are fixed now. `RELEASE_NOTES.md` and `CHANGELOG.md` are
the accurate, current record; this file is for picking the work back up.

## Completed through v5.1.0

- Full v4.0.0 feature set (download engine: shortcuts/resourceKey, resume,
  bandwidth limit, multi-thread; queue: pause/resume, reorder, smart naming,
  duplicate detection; search, stats; Chrome/Safari extensions + Share
  Extension scaffolding).
- v5.1.0: Chrome extension bug fixes (a JS `class`-before-declaration bug
  was crashing the content script outright), `dropdrive://download?url=`
  standardized as the one deep-link form every integration emits, Menu Bar
  Mode wired to the same live `DropDriveViewModel.shared` instance as the
  main window (previously two independent, silently-diverging instances),
  dead code removed (unwired deep-link handler in `DropDriveApp.swift`,
  `EnvironmentKeys.swift`, a forked/drifted duplicate of the extension JS
  sitting unreferenced inside the Safari project).

## Architecture

- `DropDriveViewModel.shared` — the one instance of the app's state
  machine; both `ContentView` (main window) and `MenuBarView` (menu bar
  extra) read from it. Don't reintroduce a second `DropDriveViewModel()`
  instance anywhere.
- `browser-extension/chrome/{manifest.json,background.js,content.js,popup.html}`
  is the single source of truth for both browsers. The Safari project
  (`browser-extension/safari/.../DropDrive Safari Extension.xcodeproj`)
  references these files directly via a relative path in its
  `PBXFileReference` entries (`path = ../../../chrome/...`) — it does not
  own a copy. If you need to change extension behavior, edit the chrome/
  files only.
- `dropdrive://download?url=<encoded Drive link>` — the one deep link every
  integration emits. Handled in `DropDriveViewModel.handleIncomingURL(_:)`,
  wired via `ContentView`'s `.onOpenURL`. The handler doesn't actually
  inspect the host segment (any `dropdrive://<host>?url=` works), but
  `download` is the canonical form — don't introduce another one.
- `DropDriveShare/` — the native Share Extension target, hand-authored
  directly in `project.pbxproj` (no `xcodeproj`/`xcodegen` tool was
  available). Hands off the same way, via `dropdrive://download?url=`.

## Known limitations / not yet done

- **Chrome extension has not been interactively verified inside a real
  Chrome window in this session** — computer-use access was requested and
  declined. What *was* verified: JS syntax/logic review (including
  confirming the fix for the class-hoisting crash), manifest.json JSON
  validity, and an end-to-end test of the DropDrive-side deep-link handler
  via `open "dropdrive://download?url=..."` (confirmed the app launches,
  parses the link, and enters analysis — verified via accessibility-tree
  inspection, not screenshots). **Next step if picking this up:** get
  computer-use or Chrome-extension-MCP access granted, load
  `browser-extension/chrome` unpacked (or launch Chrome with
  `--load-extension=<path>` to skip the native file picker), navigate to a
  real Google Drive file, click the injected button and the context menu
  item, confirm Chrome's native "Open DropDrive?" prompt and the resulting
  queue/download/notification/Reveal-in-Finder flow.
  - Safari extension: rebuilds clean, but wasn't re-verified interactively
    in Safari this session either (out of scope per this session's
    instructions — "Chrome is the ONLY browser target... do not spend
    additional engineering effort on Safari unless fixing regressions" —
    the changes it did get were regression fixes: removing a dead
    native-messaging code path, no new Safari-specific work).
- Edge/Brave/Arc: not implemented, intentionally (out of scope, Chrome
  only per this session's mandate).
- `GoogleAPIKey` in `Info.plist` is still a placeholder — anonymous public
  access always falls back to Google sign-in.
- `UpdateChecker.repository` is still `nil` — no GitHub repo configured yet
  (explicit prior decision, not an oversight).
- Not notarized — fine for direct/team distribution, not for wide public
  distribution.

## Build / release state

- `xcodebuild -scheme DropDrive -configuration Debug|Release build` — both
  clean, zero app-code warnings.
- Safari extension project builds clean too.
- `dist/DropDrive-v5.1.0.dmg` built and verified (mounts, correctly signed
  with team `YM8Y88VSBF`). Prior release DMGs in `dist/` untouched.
- Tag `v5.1.0` created on this session's final commit. The pre-existing
  `v5.0.0` tag was left untouched (points at an earlier commit, per this
  session's explicit instruction not to rewrite/move existing tags).

## Exact next step

Get interactive browser access (computer-use or Chrome MCP) approved, then
do the real click-through QA described above. Everything else for v5.1.0 is
done.

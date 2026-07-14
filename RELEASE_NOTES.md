# DropDrive v5.2.0 Release Notes

A production-readiness pass on top of v5.1.0: no new features, no UI redesign —
just a bug hunt across the download engine and Menu Bar Mode, and fixes for
every confirmed issue found.

## What's fixed

### Download engine
- **Cancel/pause during a multi-threaded download used to be silently
  ignored.** If a large file was downloading over multiple concurrent ranged
  connections and the user cancelled or paused it, the code couldn't tell
  "the user stopped this" apart from "one connection had a transient
  failure" (both surface as the same error type from a cancelled part), so
  it treated it as the latter and started an entirely new single-stream
  download instead of stopping. Fixed by checking the actual task
  cancellation state rather than inferring intent from the error.

### Menu Bar Mode
- **The popover rendered far too narrow**, squeezing the Pause/Resume/
  Cancel and Open Window/Preferences button rows into a broken, wrapped
  layout. `MenuBarExtra` needs `.menuBarExtraStyle(.window)` for custom
  SwiftUI content — without it, macOS sizes the popover as if it were a
  traditional menu, which doesn't respect explicit frames or `HStack`s.
- **"Open Window" could open a second, duplicate main window** instead of
  bringing the existing one forward. The button's own duplicate-prevention
  logic was already correct; the actual cause was that activating the app
  independently triggered AppKit's default window-reopen behavior. Fixed
  with an `NSApplicationDelegate` that makes reopen a no-op when a window
  is already open.
- The active-download and queue rows showed the raw Drive URL instead of
  the file/folder name (the main window already showed the name
  correctly — this was a Menu-Bar-Mode-only regression).
- Several icon-only buttons (quit, preferences, reveal/retry/remove) had a
  hover tooltip but no VoiceOver accessibility label; added.

## Verified, unchanged

- Zero leaks, stable idle CPU/memory across repeated open/close cycles.
- Debug and Release builds clean, zero app-code warnings.
- Safari extension project rebuilds clean — untouched this release, per
  scope (Chrome is the only browser worked on; Safari gets attention only
  for regressions, and none were found).

## Upgrading

Download `DropDrive-v5.2.0.dmg`, open it, and drag DropDrive.app to
Applications, replacing the previous version. Everything carries over —
sign-in, history, preferences, queue.

## Known limitations in this release

- The multi-threaded-download cancellation fix and the Menu Bar Mode fixes
  were verified via direct interactive testing (Computer Use driving the
  real app) and, for the download engine, static analysis of the
  concurrency logic — a live cancel-mid-download-of-a-large-file test
  wasn't possible in this session (no accessible large test file), so the
  fix's logic is correct by inspection and unit-level reasoning but not
  yet confirmed against a real multi-gigabyte transfer.
- Chrome extension interactive QA (loading it in a real browser tab,
  clicking through to Google Drive) wasn't performed this session —
  browser automation access wasn't available; this release didn't change
  the Chrome extension anyway (v5.1.0 already covered it, and no
  regressions were found there).
- Everything listed in v5.1.0's and v4.0.0's known limitations still
  applies (`GoogleAPIKey` unset, update checker inactive pending a real
  repo, not notarized).

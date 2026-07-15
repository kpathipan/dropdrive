# DropDrive v5.5.0 Release Notes

A visual pass over DropDrive: a new app icon, a proper logo-plus-wordmark
header, a main window that fits its content, a visible reveal-in-Finder
button, and a lighter menu bar.

## What changed

### New app icon
The generic tray-and-arrow glyph is replaced everywhere (all sizes,
16→1024) by a document-dropping-into-a-tray mark, extracted pixel-exact
from the source render and masked to a transparent squircle. The menu bar
keeps a monochrome SF Symbol template, which is the correct native style
there.

### Logo and two-color wordmark
The main window and menu bar now show the logo above "DropDrive", with
`Drop` in the primary label color and `Drive` in blue. `Drop` adapts to
light/dark mode instead of using a fixed dark hex that would vanish on a
dark background.

### Visible reveal-in-Finder button
Recent Downloads used to hide "Reveal in Finder" in the right-click menu
only. Each row with a file on disk now shows an always-visible folder
button (blue on hover); the context menu still works.

### Menu bar simplified
The dropdown no longer mirrors the whole app. It's now a paste-link field
(submits and brings the window forward), a single status line — live
progress with pause/cancel while downloading, or a short
"N downloads today" / "Ready" line when idle — and Open DropDrive /
Preferences buttons.

### Main window fits its content
It previously opened about 900pt wide with the 360pt content stranded in
the middle. `.frame(maxWidth:)` only bounds the view, and
`.windowResizability(.automatic)` let the window ignore it; switching to
`.contentSize` makes the window hug its content, opening compact at about
460×570.

## What was verified

- Built and installed v5.5.0; the new icon shows on the Dock and the
  logo-plus-two-color-wordmark header renders correctly in the main
  window (light and dark).
- The main window opens at ~460×570 on a cleared frame, no longer 900 wide.

## What wasn't verified live

- The **menu bar dropdown** couldn't be opened for a screenshot: its
  status-bar icon is hidden behind the display notch on the test machine.
  The code builds and uses only existing view-model APIs, and it shares
  the same header/logo that the main window renders correctly.
- The **reveal-in-Finder button** is in place but wasn't seen on a real
  row — Recent Downloads was empty at test time, so there was no finished
  download to render it against.

## Upgrading

Download `DropDrive-v5.5.0-adhoc.dmg`, open it, and drag DropDrive.app to
Applications, replacing the previous version. Because the app isn't
notarized, the first launch may be blocked — the DMG includes an
"If DropDrive won't open" note with the one-time Terminal command
(`xattr -d com.apple.quarantine /Applications/DropDrive.app`).

## Known limitations

- Everything above in "What wasn't verified live."
- Ad-hoc signed, not notarized — the quarantine step above is needed on
  first launch on another Mac.
- Chrome extension is loaded unpacked (not on the Chrome Web Store).
- Update checker inactive pending a public repository.

# DropDrive v5.3.0 Release Notes

The final Chrome integration sprint: an Internet-Download-Manager-style
workflow on the real Google Drive selection UI, not just single-file detail
pages. **This release could not be verified against the live Google Drive
website** — see "What could not be verified" below before relying on it.

## What changed

### The extension now understands Drive's actual selection UI
The previous version only recognized a Drive item from the page URL
(`/file/d/<id>/...` or `/folders/<id>`), which only exists when you're
already on that item's own detail page. It did nothing on Drive's normal
file-listing view, which is how selection actually works day to day. It now
reads Drive's real selection state (`aria-selected="true"` elements carrying
Drive's own `data-id`), which works for:
- a single file or folder,
- multiple files,
- multiple folders,
- a mixed selection of both,
- in both List and Grid view,

sent to DropDrive in the order they appear in Drive's own list/grid.

### Toolbar button, next to Download, not a new one floating alone
Finds Drive's own Download button (`data-tooltip`/`aria-label="Download"`)
and inserts DropDrive's icon directly beside it, sized to match rather than
an oversized custom button, with a "Download with DropDrive" tooltip. It
appears and disappears along with Drive's own Download button (i.e., only
when something is selected).

### Context menu, inside Drive's own menu this time
The previous version only registered a `chrome.contextMenus` entry, which
is the *browser's* native right-click menu — Google Drive renders its own
custom right-click menu and prevents the native one from appearing on a
file/folder row at all, so that entry never actually showed up where it was
supposed to. This release detects Drive's own menu opening and inserts a
"DropDrive" item directly below "Download" inside it, cloned from Drive's
own DOM so it inherits the surrounding styling automatically.

### Toast, deep link, multi-selection plumbing
- "✓ Sent to DropDrive" toast on send; re-sending resets its timer instead
  of stacking a second toast.
- `dropdrive://download?url=` is unchanged as the one endpoint; a
  multi-selection repeats the `url` parameter once per item in order
  (`?url=A&url=B`) rather than introducing a new endpoint or format. The
  DropDrive app was given a small, corresponding change to analyze and
  queue multiple links from one deep link, in order, without interrupting
  a batch with per-item duplicate-download prompts.
- Real extension icons (16/48/128), derived from DropDrive's own app icon.

## What could not be verified

This is the important section. Per your instruction, I'm stating plainly
what wasn't verified rather than claiming the QA checklist passed:

**Interactive browser access was unavailable this entire session.** Computer
Use grants browsers screenshot-only access by design (no clicks or typing),
and the Claude-in-Chrome extension wasn't connected. I could not: load the
unpacked extension via the real Chrome UI, open drive.google.com
interactively, select files, click the toolbar button or context menu item,
switch List/Grid view, check the DevTools console, or confirm the
DropDrive-launches → queue → download → notification → Reveal-in-Finder
chain from the Chrome side.

**What I did instead:**
- Wrote every selector defensively (layered primary + fallback strategies)
  based on documented/well-established Google Drive DOM conventions
  (`data-tooltip`, `aria-label`, `role="menuitem"`, `data-id`,
  `aria-selected`) rather than guessing at Drive's own generated CSS class
  names, which are unstable.
- Syntax-checked both `content.js` and `background.js` (no parse errors).
- Validated `manifest.json` as well-formed JSON with real icon files
  present (no missing-icon gap).
- Verified, as an isolated and directly testable unit, that Swift's
  `URLComponents` correctly preserves multiple same-named `url=` query
  items in order — the specific mechanism multi-selection ordering depends
  on.
- Sent a real (fake-content) multi-item deep link to a running DropDrive
  and confirmed the app doesn't crash and its UI stays clean (no error
  state leaking into the paste box from a silent background batch).
- Confirmed the companion Safari extension project still builds clean
  (no regression — Safari shares the same JS source files and wasn't
  otherwise touched, per this sprint's scope).

**A concrete, observed risk, not just a theoretical one:** mid-session, a
real Chrome window with Google Drive already open was visible (Computer
Use's screenshot-only access shows what's on screen even though it can't
click). That Drive session was in **Thai** ("หน้าแรก - Google ไดรฟ์"). The
context-menu matching in this release looks for the word "Download" in
English. If Google localizes `data-tooltip`/`aria-label` values (not just
the visible menu text) for non-English UI, the toolbar-button selector
would also fail. This could not be confirmed either way without DOM
inspection access. If Drive's own internal data attributes stay in English
regardless of display language, this is a non-issue; if not, the extension
will currently do nothing (fail silently, not break) for non-English Drive
locales. This needs a real check before wide distribution.

## Upgrading

Download `DropDrive-v5.3.0.dmg`, open it, and drag DropDrive.app to
Applications, replacing the previous version. For the extension: reload it
from `chrome://extensions` (unpacked, not on the Chrome Web Store).

## Known limitations

- Everything above in "What could not be verified."
- Everything listed in v5.2.0's, v5.1.0's, and v4.0.0's known limitations
  still applies (`GoogleAPIKey` unset, update checker inactive pending a
  real repo, not notarized).

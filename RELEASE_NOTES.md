# DropDrive v5.4.0 Release Notes

The first release where the Chrome integration was actually exercised
against the live drive.google.com UI, end to end, rather than reasoned
about from documented DOM conventions. Every bug below was found and fixed
by watching the real thing fail, not by inspection.

## What changed

### Chrome extension actually works now
Three real, live-confirmed bugs were blocking the whole workflow:
- The selection toolbar's actual ARIA role is `region`, not `toolbar` as
  originally assumed — the toolbar-button selector was scoped to a role
  that never matched.
- `data-tooltip`/`aria-label` values are localized by Google, not just the
  visible text (confirmed on a Thai-locale account: `data-tooltip` reads
  "ดาวน์โหลด", not "Download"). The Download-button and menu-item matchers
  now check a small list of confirmed labels instead of English only.
- The item context menu renders in two passes — a quick partial menu, then
  a fuller one moments later — and the second pass was silently reshuffling
  the DOM, leaving the injected "DropDrive" entry stranded at the top of
  the menu instead of directly under "Download". Injection now re-checks
  itself on every later menu mutation instead of running once.

### Auth flow no longer strands the user
Clicking the Chrome toolbar button on a private file opens DropDrive and
asks you to sign in — previously that was a dead end; nothing happened
after signing in. The pending link is now stored and retried automatically
once sign-in succeeds, so the file queues itself with no need to go back to
Chrome and re-click.

### Toolbar button redesign
A small solid-blue pill (cloud-down icon + "DropDrive" text) instead of a
bare gray icon that read too close to Drive's own Download button at a
glance. Sized and positioned off Drive's own Download button so it sits
level with the rest of the row regardless of how Drive lays it out.

### macOS 14.0, not 26.5
`MACOSX_DEPLOYMENT_TARGET` was left at Xcode's project-creation default
(`26.5`) rather than the app's actual floor. Lowered to `14.0`, the real
requirement set by `@Observable`/`Observation`. Along the way, a
`.dropDestination` call in the queue reorder handler was silently binding
to a macOS-26.0-only overload because its closure returned `Void` instead
of `Bool` — an SDK-driven trap, not an intentional 26.0 requirement — fixed
by matching the older overload's signature.

## What was verified — for real this time

Every item below was watched happening live against a real Google account
and a real file, not simulated:

- Selected a private file on drive.google.com, clicked the Chrome toolbar
  button, confirmed the "Sent to DropDrive" toast.
- DropDrive launched via `dropdrive://download?url=...`, received the link,
  and pre-filled it automatically.
- The file needed Google sign-in; after signing in, it queued itself
  automatically — no re-pasting the link.
- A real 1.95 GB file downloaded to 100%; the resulting file was confirmed
  on disk at the correct size and as valid, unstructured video data (not
  truncated or corrupted).
- "Reveal in Finder" opened Finder with the completed file already
  selected.
- Right-clicking a file in Drive shows "DropDrive" directly under
  Drive's own "Download" entry.

## What still isn't verified

- Multiple-file selection and folder selection weren't re-exercised this
  round — only a single private file went through the full live flow
  above. The underlying selection-reading code is unchanged from 5.3.0's
  design (`[aria-selected="true"][data-id]`, meant to work for both), but
  hasn't been re-watched live since the selector fixes landed.
- Safari extension wasn't touched or re-tested this release.
- Still signed with a local Apple Development certificate, not a Developer
  ID — not notarized, same as every release since 4.0.0. A machine building
  this from source needs an Apple ID added under Xcode's own Accounts
  settings (Xcode → Settings → Accounts) before `-allowProvisioningUpdates`
  can register the building device automatically; without one, the build
  fails outright with "No Accounts", not a signing error, which cost real
  time to trace back to on this machine.

## Upgrading

Download `DropDrive-v5.4.0.dmg`, open it, and drag DropDrive.app to
Applications, replacing the previous version. For the extension: reload it
from `chrome://extensions` (unpacked, not on the Chrome Web Store), then
refresh any open drive.google.com tabs.

## Known limitations

- Everything above in "What still isn't verified."
- `GoogleAPIKey`/OAuth client is configured and working (confirmed live
  this release — earlier notes describing it as unset are stale).
- Update checker inactive pending a public repository; not notarized.

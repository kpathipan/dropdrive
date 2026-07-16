# DropDrive v5.6.1 Release Notes

Sign-in works again on a freely-distributed build, and two controls that
looked clickable but weren't now are.

## The headline: sign-in could never complete

"It asks me to connect while already connected" turned out to be two
separate faults stacked, neither of them in the app's own logic.

**GoogleSignIn couldn't write to the keychain.** It stores its session in
the *data-protection* keychain, which on macOS requires an
`application-identifier` entitlement that only a real Apple Team signature
provides. An ad-hoc signed build has no team, so every write failed with
`errSecMissingEntitlement` (-34018), and GID reported it as "keychain
error" (-2) the instant the OAuth redirect succeeded — leaving the app
permanently signed out. An ad-hoc test binary confirmed it: -34018 from
the data-protection keychain, `errSecSuccess` from the file-based one.

`LoginManager` now drives **AppAuth + GTMAppAuth directly** — both already
linked — and asks for their file-based keychain store, which needs no
entitlement. No fork, no private API, no new dependency.

**The account chip lied.** It fell back to a cached account even when no
session could be restored, so the header claimed "connected" while every
private-file analysis demanded sign-in. It now only shows an account that
genuinely restores.

**Google Cloud consent screen** was also set to Internal, which rejected
any account outside the owning Workspace with `403 org_internal` before the
keychain even came into play. It's now External / in production.

## Also fixed in 5.6.1

- **The queue's ✕ did nothing.** Cancelled rows drew an `xmark.circle.fill`
  status icon — the standard remove glyph — while Remove was right-click
  only. Every row that isn't mid-download now has a real remove button, and
  the cancelled icon is `slash.circle` so it stops posing as one.
- **The Chrome button died silently after an extension reload.** A stale
  content script threw an uncaught "Extension context invalidated"; it now
  says "reload this page" instead.
- Extension manifest version tracks the app again (it had sat at 5.4.4).

## What was verified

- A real **73 GB / 320-file** download across two private Drive folders,
  end to end.
- Sign-in completes with the `drive.readonly` scope; the session survives
  quit/relaunch and an app update.
- The account chip populates, and Drive API calls authenticate.

## What wasn't verified

- The **queue remove button** and the **stale-extension toast** compile and
  ship but haven't been seen running — the queue was empty at test time,
  and the extension needs a manual reload first.
- Nothing has been tested on anyone else's Mac.

## Upgrading

Download `DropDrive-v5.6.1-adhoc.dmg`, open it, drag DropDrive.app to
Applications, replacing the previous version.

- The app isn't notarized, so the first launch is blocked — the DMG
  includes an "If DropDrive won't open" note with the one-time Terminal
  command (`xattr -d com.apple.quarantine /Applications/DropDrive.app`).
- **After updating, macOS asks once for keychain access** ("DropDrive wants
  to use your keychain"). Choose Always Allow — each ad-hoc rebuild changes
  the app's signature, so the stored session's ACL no longer matches until
  you re-approve it. The session itself survives.
- For the Chrome extension: reload it from `chrome://extensions`, then
  refresh any open drive.google.com tabs.

## Known limitations

- Everything above in "What wasn't verified."
- **The ad-hoc build is not sandboxed.** A sandboxed app can't reach the
  keychain without `keychain-access-groups`, which macOS only honours behind
  a real Team prefix; self-assigning one makes launchd refuse to spawn the
  app. Re-signing with the sandbox restored reproduced the failure. The
  Team-signed build keeps its sandbox; the Share extension stays sandboxed.
- Not notarized, so the quarantine step above is required on every Mac.
- Google hasn't verified the OAuth app, so sign-in shows an "unverified
  app" screen (Advanced → Go to DropDrive) and is capped at 100 users.
- Chrome extension is loaded unpacked, not from the Web Store.
- Update checker inactive pending a public repository.

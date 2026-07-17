# DropDrive v5.8.0 Release Notes

DropDrive moved into the menu bar. There is no Dock icon and no main
window any more — the whole app now lives in a single popover under its
menu bar icon.

## The new shape

Click the tray icon in the menu bar and the full app opens right there. A
narrow icon rail on the left switches between four panes:

- **Queue** — the paste field, link analysis, and the live download queue
  with per-item progress, pause/resume, and reveal-in-Finder. The rail
  icon shows a badge with the number of active and pending downloads.
- **Recent** — the searchable download history, with Reveal in Finder and
  Copy Google Drive Link on every entry.
- **Statistics** — the local-only download counters.
- **Preferences** — everything the old Settings window had, plus an About
  section with the version number. Quit is the power button at the bottom
  of the rail.

Dragging a Drive link from a browser onto the popover still works, as do
the Share menu, deep links, sign-in, notifications, and everything else
under the hood — the download engine is untouched from 5.7.1.

## Why

DropDrive is a "paste a link, wait, done" utility — it never needed a
persistent window or a Dock presence. As a menu bar app it stays out of
the way, and with Launch at Login enabled it's always one click away.

## Upgrading

Open the DMG and drag DropDrive.app to Applications as usual. After
launching, look for the tray icon in the top-right of the menu bar —
there is deliberately no Dock icon and no window on launch now, so the
menu bar icon *is* the app.

# DropDrive v5.10.0 Release Notes

Two additions: pick your theme, and never start a download the disk
can't hold.

## Theme: System / Light / Dark

Preferences gained a Theme picker. Light is the design you know; Dark is
its warm-dark counterpart (near-black canvas, dark cards, a brighter
accent blue that reads properly on black); System follows the Mac's
appearance and switches live when macOS does.

## Disk space check

Starting a queue now checks the destination volume first. If the known
download size plus a 200 MB headroom doesn't fit, DropDrive tells you
how much it needs versus how much is free — you can still choose
"Download anyway". Files whose size Drive doesn't report are counted as
zero, so the warning errs on the quiet side rather than crying wolf.

## Upgrading

Quit the old version (menu bar icon → power button), open the DMG, drag
DropDrive.app to Applications, Replace. First launch may need
right-click → Open once.

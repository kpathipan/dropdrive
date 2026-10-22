# Local verification — 2026-10-22

Scope: macOS local build of 6.25.4 (51), with `DDLocalAutomationBuild=true`.
Installed over `/Applications/DropDrive.app` only while its queue was empty.
No tag, push, public release, Windows change or Google credential extraction.

## Passed

- Debug and Release Xcode builds; stable designated requirement and deep/strict
  code signature verification of the installed app.
- `scripts/test-regressions.sh`: ALL PASS, including 9 automation validation /
  serialization checks.
- `npm --prefix mcp test`: 6 passing tests, including IPC permissions, symlinks,
  timeout request preservation, user-action status and real-file verification.
- Official MCP SDK stdio handshake lists all five tools.
- Real public Google Drive folder analysis -> download -> completed -> verified.
  Fixture: `https://drive.google.com/drive/folders/12zxlvJtuHFV6awc3AINaNHnfvRttPv0i`.
  Job: `C643F2B3-2472-475C-AEA4-1A178EBC6FF2`.
  Output: `/Users/mac/Downloads/DropDrive MCP Test c643f2b3/gdown.pptx`.
  Expected/actual: 1/1 file, actual size 32,110 bytes, zero partial files.
  The source is a Google document export; estimated source bytes need not equal
  the exported PowerPoint size. `unzip -t` passed all document entries.
- Same request replay before and after application restart returned the same
  completed job and output, without starting another download.
- Conflicting arguments with the same ID -> `id_conflict`; duplicate source ->
  `duplicate_completed`; unknown job -> `unknown_job`.
- Installed final build reports `failed/invalid_format` for trying to convert
  the non-video fixture to MP3, without downloading. Traversal name is rejected.
- Final queue empty; one original test file preserved; app running normally.

## Handoff boundary

`codex mcp get dropdrive --json` confirms enabled stdio configuration using
`/opt/homebrew/bin/node` and this checkout's `mcp/server.mjs`.

The subsequent chat turn exposed all five native `mcp__dropdrive` tools.
Direct calls from this chat to `dropdrive_health` and `dropdrive_verify` passed:
the installed app responded as 6.25.4, the recorded job remained completed, and
verification found 1/1 file (32,110 bytes) with zero partials or symlinks.
Host-tool activation is now verified. This follow-up did not start a duplicate
download or restart the user's Codex session.

Saved-queue restoration/cancellation reporting has compiled and its adapter
wait behavior has unit coverage; no user queue was fabricated, paused or
discarded merely to test it. Private-account Google downloads and video/MP3
transfers were not newly exercised in this MCP smoke test.

The recoverable pre-install app backup is outside Applications at
`~/Library/Application Support/DropDrive/Local Build Backups/DropDrive-6.25.4-before-local-mcp.zip`.
It contains the previous app, not downloads or credentials. Test files are
preserved; no user files were removed.

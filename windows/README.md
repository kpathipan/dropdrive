# DropDrive for Windows

Windows-first desktop client with a normal resizable window, background tray
presence, direct/media downloads and automatic in-place updates.

## Local Windows build

Requires Windows 10/11 and the .NET 10 SDK.

```powershell
./fetch-tools.ps1
./build-windows.ps1 -Version 0.6.0
```

The installer is written to `artifacts/releases/com.dropdrive.windows-win-Setup.exe`.
Installed builds check the public GitHub release feed at most once every 24
hours. Manual checks bypass that interval. Development builds intentionally
skip update installation.

## Release

Push a `windows-v<semver>` tag only after testing the installer on Windows. The
Windows workflow builds the EXE, creates the Velopack feed and publishes that
feed to a GitHub Release. Signing variables can be added to the workflow once an
Authenticode certificate is available.

## Windows 0.6 parity scope

Implemented from the Mac flow: compact dark/Thai window and inline settings,
review with artwork and editable title, quality/MP3/subtitles/clip/chapter
options, collection cards/list with three sizes and mixed-state select-all,
anonymous Drive folder enumeration, per-item destinations, persistent
pause/resume/retry queue, queue ordering, recent search/open/reveal/copy/repeat,
fixed metric columns, bandwidth/compatible-video/theme preferences, and
24-hour update checks while running with installation deferred until idle.

This is **not full Mac feature parity**. Private/multiple Google accounts,
Drive changed-only snapshots, playable remote-video Quick Look, phone inbox,
OS toast/sound notifications and launch-at-login remain unimplemented.
Space preview shows a thumbnail, not remote video playback. Public Drive's
anonymous HTML listing is not the authenticated Drive API; inaccessible or
unsupported listings must fail explicitly. TikTok photo carousels are not yet
handled by the original-video route. Live platform availability is separate
from deterministic regression checks and can vary by account/region.

CI runs the production UI + core regression checks on Windows, saves six
rendered screenshots, and smoke-tests the packaged executable before publishing
a tag. Checks cover real control interactions and an HTTP download fixture
through the actual queue. See parity-checklist.md for exact limitations.

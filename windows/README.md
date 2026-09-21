# DropDrive for Windows

Windows-first desktop client with a normal resizable window, background tray
presence, direct/media downloads and automatic in-place updates.

## Local Windows build

Requires Windows 10/11 and the .NET 10 SDK.

```powershell
./fetch-tools.ps1
./build-windows.ps1 -Version 0.7.0
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

## Windows 0.7 parity scope

Implemented from the Mac flow: compact dark/Thai window and inline settings,
review with artwork and editable title, quality/MP3/subtitles/clip/chapter
options, collection cards/list with three sizes and mixed-state select-all,
anonymous Drive folder enumeration, per-item destinations, persistent
pause/resume/retry queue, queue ordering, recent search/open/reveal/copy/repeat,
fixed metric columns, bandwidth/compatible-video/theme preferences, and
24-hour update checks while running with installation deferred until idle.

The reference is Mac **6.24.4**. Version 0.7 adds completion receipts and
new/changed-file selection, TikTok photo collections with separate audio,
pause/resume-all, bounded network retries, destination recovery, recent
destinations, optional synced phone inbox, local statistics, custom bandwidth,
native Windows notifications/sound, startup, Ctrl+Shift+D, single instance,
Thai/English resources, and keep-awake only during downloads.

Google sign-in is **optional**: public Drive downloads work without it.
Multiple accounts can be added, with a preferred account and fallback to
other authorized accounts during analysis. Signed-in Drive uses the API for
private/shared files, folders and Workspace exports. Tokens are protected by
Windows DPAPI for the current user, separately from queue/settings, at a
stable path that does not change on app updates. Removing an account removes
local access only; it does not delete downloads or revoke other devices.

Space preview shows an inline thumbnail/icon, matching the reference Mac
pre-download browser; it is not remote video playback. Completed files open
in the user's default Windows app. Anonymous Drive HTML listings expose less
change metadata than the authenticated API. Live media availability is separate
from deterministic regression checks and can vary by account/region/network.
See [parity-checklist.md](parity-checklist.md) for verification and limitations.

## Optional Google sign-in configuration

Create an OAuth client of type **Desktop app** in the existing DropDrive Google
Cloud project, with Drive API enabled and the consent screen configured for
`openid email profile` and `drive.readonly`. Do not reuse the Mac custom-scheme
client. Download the `installed` client JSON into the ignored local path
`DropDrive.Windows/oauth-client.json`; never commit it. CI reads the same JSON
from the repository secret `GOOGLE_DESKTOP_OAUTH_JSON` and embeds it in the app.
Native client credentials are not a substitute for PKCE or user consent.

Development builds can run without this configuration (sign-in is disabled).
**Tag releases fail if it is absent.** Release validation covers browser consent,
return-to-app refresh, private transfer, token refresh, multiple accounts and
signed-out public downloads through live checks and Windows fixtures. Record
any unverified end-to-end paths explicitly in the parity checklist; automated
fixtures alone do not prove the Google Cloud configuration works.

An explicit interactive service smoke check is available with
`dotnet run --project DropDrive.Windows.Checks -- --live-google-login <client-json-path>`.
Open the printed authorization URL in the browser and complete consent. This
check uses in-memory tokens only, exercises the production PKCE/loopback and
refresh flow, and reads a known public fixture through the authenticated API;
it does not enumerate or download private files. See the parity checklist for
which live and Windows-specific checks have actually passed.

CI runs the production UI + core regression checks on Windows, saves eight
rendered screenshots, and smoke-tests the packaged executable before publishing
a tag. Checks cover real control interactions and an HTTP download fixture
through the actual queue. See parity-checklist.md for exact limitations.

The optional --live-drive check additionally downloads a public Google Slides
fixture through the production Drive folder path. It verifies a real PPTX, not
an HTML permission page, with no duplicate destination wrapper.
YouTube's JavaScript runtime is bundled (QuickJS-NG 0.16.2, SHA-256 verified at
build time) so the user does not have to install Node/Deno separately.
The bundled Noto Sans Thai font avoids differences in Thai fallback fonts.

The disposable Windows runner also installs 0.6.0, installs the new build over
it, verifies the stable executable/updater paths and retained settings/queue,
and opens the installed app. This tests installer upgrades, not the remote
GitHub auto-update download path. A separate post-publication job launches the
old installed version against the public feed, waits for its automatic update,
and verifies the new version and retained settings/paused queue. Native checks
also exercise tray/hotkey registration, notification activation, startup
settings and DPAPI persistence. Provider probes save PASS/UNAVAILABLE results;
a green workflow alone does not mean every external website allowed access.

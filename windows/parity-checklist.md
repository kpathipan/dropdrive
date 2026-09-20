# Windows / Mac parity verification — 0.7.0 candidate

The source at macOS tag **v6.24.4**, not the first Windows prototype, is the reference.
This is a release candidate, not a statement that 0.7.0 is published.

| Workflow | Implementation / verification |
| --- | --- |
| Compact dark Thai home, inline settings, underline tabs | Production XAML rendering and navigation checks |
| Analysis and review separate from queue | Review/confirm exercises actual queue and HTTP writer |
| Idle Download / busy Queue action | Changes both directions while review is open |
| Rename, cover, destination, duplicate review including MP3 | Review controls, metadata and options fixtures |
| Cards, three sizes, list, individual / all / mixed selection | Checkbox bindings after deselect-all; search preserves hidden selection |
| Space preview | Inline thumbnail/icon as in the reference Mac pre-download browser; real Space key events do not toggle selection |
| Public Drive folders, nested contents, Docs export | HTML/URL fixtures and optional live public Slides download; no login required |
| Optional multi-account Google Drive | PKCE/state, token refresh, account fallback, pagination, exports, resource keys and authenticated byte-transfer fixtures; DPAPI round-trip on Windows |
| New/changed selection | Bounded completion receipts; only successful selected entries recorded; API fingerprints when signed in |
| Destination safety | Missing-directory guard and relative-folder checks; no duplicate root wrapper |
| Pause, resume, retry, queue ordering | HTTP Range/If-Range fixture; persistent job IDs |
| Pause/resume-all, transient recovery | Actual queue/HTTP checks, bounded backoff and destination recovery |
| Fixed progress/speed/ETA widths | Window/header bounds unchanged by wide values |
| History search/open/reveal/copy/repeat | Saved result path and UI controls; shell actions need desktop integration testing |
| Media quality/MP3, subtitles, clip, chapters, artwork | Argument fixtures; live providers not all end-to-end tested |
| TikTok original-video route | Player fixture excludes download_addr; live availability not guaranteed |
| TikTok photo collections | Original image/audio fixtures, trusted CDN checks and selected-entry downloads |
| 24-hour updates, manual bypass, idle installation | Cadence/startup checks; CI installs 0.6.0 then upgrades in-place; separate post-publication public-feed test |
| Bandwidth, compatible video, theme, open folder preference | Persisted controls and argument fixtures |
| Native notifications/sound, startup, hotkey | Windows API integration checks and simulated notification activation; desktop notification display still depends on Windows settings |
| Phone inbox | Opt-in synced folder; durable acceptance, original-file archive, modification-race fixtures |
| Local statistics, recent destinations, single instance | Persisted models, installed second-launch test; no cloud telemetry |
| Thai/English | Resource/UI checks; some advanced dynamic errors still use Thai |

## Release blockers and intentional differences

- Real Google Desktop OAuth client and browser consent/private-file smoke test
  are required before release; service fixtures alone cannot validate them.
- Windows uses a small normal window/tray, native file picker and default file
  viewer, rather than macOS menubar/Quick Look/Keychain.
- Anonymous Drive change detection cannot reliably detect same-name content
  edits without exposed fingerprints. Signed-in API metadata is richer.
- Media providers can reject datacenter IPs, require login, or remove fixtures;
  inspect the provider report rather than treating UNAVAILABLE as a pass.
- Compatible-video selection is not a guarantee of H.264 transcoding for every
  fallback source. There is no playable remote-video preview.

## Release gate

- Warnings treated as errors; core and actual-control checks pass on Windows.
- Inspect CI-rendered empty, settings, cards, list, history, active-transfer images.
- Packaged executable opens; Velopack feed and packages exist.
- Disposable runner verifies a real installed upgrade; verify the separate public-feed job after publication.
- Configure and manually verify Google OAuth before creating the release tag.
- Release notes disclose remaining gaps; never describe this as full parity.

## Regression / rollback

If startup, selection, destination safety or persistent queue fails, do not publish.
After publication, ship a higher-version corrective build. Do not rewrite a
published package/hash or downgrade the feed. Keep 0.6.0 assets intact.

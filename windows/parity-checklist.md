# Windows / Mac parity verification — 0.6.0

The macOS source, not the first Windows prototype, is the reference.

| Workflow | Implementation / verification |
| --- | --- |
| Compact dark Thai home, inline settings, underline tabs | Production XAML rendering and navigation checks |
| Analysis and review separate from queue | Review/confirm exercises actual queue and HTTP writer |
| Idle Download / busy Queue action | Changes both directions while review is open |
| Rename, cover, destination, duplicate review including MP3 | Review controls, metadata and options fixtures |
| Cards, three sizes, list, individual / all / mixed selection | Checkbox bindings after deselect-all; search preserves hidden selection |
| Space preview | Thumbnail only, not remote video playback |
| Public Drive folders, nested contents, Docs export | HTML and URL fixtures; no OAuth/cookie access |
| Destination safety | Missing-directory guard and relative-folder checks; no duplicate root wrapper |
| Pause, resume, retry, queue ordering | HTTP Range/If-Range fixture; persistent job IDs |
| Fixed progress/speed/ETA widths | Window/header bounds unchanged by wide values |
| History search/open/reveal/copy/repeat | Saved result path and UI controls; shell actions need desktop integration testing |
| Media quality/MP3, subtitles, clip, chapters, artwork | Argument fixtures; live providers not all end-to-end tested |
| TikTok original-video route | Player fixture excludes download_addr; live availability not guaranteed |
| 24-hour updates, manual bypass, idle installation | Cadence checks and packaged startup smoke; no live destructive update test |
| Bandwidth, compatible video, theme, open folder preference | Persisted controls and argument fixtures |

Still absent: private/multiple Google accounts, TikTok photo-carousel parity,
Drive changed-only snapshots, phone inbox, OS toast/sound, launch at login,
language switching (interface is Thai).

## Release gate

- Warnings treated as errors; core and actual-control checks pass on Windows.
- Inspect CI-rendered empty, settings, cards, list, history, active-transfer images.
- Packaged executable opens; Velopack feed and packages exist.
- Release notes disclose remaining gaps; never describe this as full parity.

## Regression / rollback

If startup, selection, destination safety or persistent queue fails, do not publish.
After publication, ship a higher-version corrective build. Do not rewrite a
published package/hash or downgrade the feed. Keep 0.5.1 assets intact.

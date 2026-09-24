# Mac + Windows: one feature contract, one release

Status: implementation pushed and Windows online build/installed-upgrade checks
passed ([initial 6.25.0 run](https://github.com/kpathipan/dropdrive/actions/runs/35682633755)).
Not published or validated as a complete paired installed upgrade. This is not
a claim of full feature parity.

## Decision (2026-09-22)

Keep native Swift/macOS and Avalonia/Windows applications. Maintain one
[feature contract](../packaging/parity-contract.json), a common future version,
one source commit and a single GitHub release containing **both** platforms.
Platform-native window/tray, credential storage and file picker remain native.
User workflows, options and expected results must match.

Rewriting both clients into a shared UI now would risk the working Mac app and
credential continuity. Separately publishing two tags allows partial rollout
and historically hid Mac updates behind the Windows latest release. One draft
with both packages keeps old Mac `/releases/latest` clients compatible and
lets Velopack find its Windows feed in the same release. New Mac/Windows
clients additionally filter the release catalogue by platform assets.

The publication is simultaneous. Installation is not synchronized across
devices: offline computers and active downloads must not be interrupted.
Both clients check passively every 24 hours; explicit update checks bypass
that interval. Mac's existing confirmation/identity verification and Windows'
idle auto-install behavior remain unchanged; do not describe automatic
installation behavior as identical yet.

## Preparation and release gate

1. Select a common stable version higher than both installed versions. Update
   and commit the Mac app/extension version and all feature changes first.
   Do not relabel or overwrite an existing release.
2. On the signing Mac run `bash scripts/prepare-mac-release.sh X.Y.Z`. It runs
   regression, performance, credential isolation, offline transfer and media
   fixture tests, then the existing stable-certificate packaging route. It
   mounts the finished DMG read-only to verify the shipped signature and bundle
   version, then writes `dist/mac-build.json`. It rejects a source change during
   preparation. It does not install, push, tag or publish.
3. Dispatch `windows.yml` at that **same commit**, with the **same version**.
   Download its `DropDrive-Windows-X.Y.Z` artifact after the whole job succeeds.
   The workflow no longer has release write permission or standalone publish.
   `windows-build.json` binds package hashes to the commit/contract and passed
   core/UI, Windows API, packaged startup and installed-upgrade steps.
4. Record evidence for every contract feature on both operating systems in
   an ignored staging file (for example `dist/parity-evidence.json`):

   ```json
   {
     "version": "X.Y.Z",
     "commit": "full git commit SHA",
     "contract_sha256": "SHA256 of packaging/parity-contract.json",
     "features": {
       "drive-public": {
         "mac": {"status": "pass", "evidence": "specific test run/log"},
         "windows": {"status": "pass", "evidence": "specific test run/log"}
       }
     }
   }
   ```

   Include every feature, not just the example above. Fixture tests establish
   code behavior, not external provider availability. Never mark blocked,
   unavailable, untested or missing scenarios as pass. Evidence is a human
   review record, not a cryptographic proof that a test actually ran.
5. Run `bash scripts/release.sh --version X.Y.Z --mac-dir dist --windows-dir
   <downloaded-artifact-directory> --evidence dist/parity-evidence.json`.
   Default mode only verifies locally; no network writes. Missing platform,
   mismatched commit/version, incomplete feed, bad hash or unverified feature
   blocks release.
6. Only after authorization, repeat with `--notes <release-notes.md> --stage`
   to upload **one draft** with both packages. It is not offered to users.
   Repeat with `--publish` to recheck the local pair, download and hash-check
   every staged asset, then publish the draft once. No forced tags/clobber.
7. Run `verify-paired-update.yml` with the shared version for the real Windows
   public-feed upgrade. On Mac verify the actual old signed installed app sees
   and installs the DMG without a new credential prompt, with queue/settings
   preserved. This Mac installed-upgrade step is still manual.

## Current parity gaps — do not mark complete

- Windows live multi-account/private Drive flow has component coverage but not
  a complete interactive Windows desktop pass.
- New public fixtures passed actual short downloads and playback validation
  through the Mac production service on September 24 (YouTube, TikTok MP3,
  Instagram, Facebook). Windows online probes must be checked independently;
  provider unavailability is not proof of parity or a passing test.
- Windows now loads visible thumbnails beyond 100 entries with bounded memory,
  includes media thumbnails in list mode, uses three densities, and renders
  nonvisual files as icon rows. This needs Windows desktop visual verification.
- Favorites and source/category destination rules, Drive MD5 verification and
  bounded-worker/chunk large-file transfers now have automated Windows coverage.
  This does not establish equal real-world transfer speed or full folder
  concurrency on both platforms.
- Mac still requests confirmation to install while Windows auto-installs when
  idle; both have the same passive cadence and manual check behavior, not an
  identical install policy.
- Advanced dynamically generated Windows errors are not all translated to
  English. Mac OS Share menu / local Quick Look integrations have native
  differences. Full parity requires scenario review, not a control count.
- The paired draft/upload/publication path is tested with local fixtures;
  neither a real paired release nor its installed upgrade has been executed.

## Tests and rollback

### Explicitly requested Windows test installers

At the user's request, `windows-test-v6.25.0` distributes only the CI-tested
Setup.exe from `82c1ed0c83f61b86c76719e22a84abc64e7399db`. It is a prerelease,
not latest, contains no update feed, and does not certify complete parity.
This exception is for manual testing only; it does not relax the stable paired
release gate. The next stable pair must exceed 6.25.0 so this installed test
build can update normally. Known provider and Windows interactive-login gaps
are disclosed in its release notes.

Shared metadata is checked out with LF on both platforms. Windows previously
converted the contract to CRLF, making receipts disagree despite identical
JSON content. The build now checks raw file bytes against the committed blob
before producing a receipt; do not rewrite an old receipt to hide a mismatch.

`ruby scripts/test-paired-release.rb` tests complete pairs, missing packages,
tampered bytes, stale contracts, incomplete evidence, wrong commit/version and
missing installer tests. Swift regressions test mixed-platform catalogues,
drafts/prereleases, missing assets and semantic version ordering. Windows checks
exercise its production update source with a mixed catalogue and thumbnails
after entry 100 via actual scrolling controls.

If startup, credentials, destination safety or queue retention fails, keep the
draft unpublished. After publication, never modify published package bytes or
roll feeds backward: prepare a higher-version **paired** fix. Preserve the last
working installers and pause further publication until the cause is verified.

References: [GitHub releases API](https://docs.github.com/en/rest/releases/releases),
[Velopack 1.2 Git release source](https://github.com/velopack/velopack/blob/1.2.0/src/lib-csharp/Sources/GitBase.cs).

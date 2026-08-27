# Changelog

All notable changes to DropDrive are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Drive folders can be reviewed as a Gallery or a List at three remembered
  sizes.** Photos and videos use Google's existing thumbnails; documents,
  audio, archives, and other files keep their native macOS file-type icons.
- **Space previews the focused folder item before download.** The preview and
  its thumbnail cache stay in memory, so browsing does not create duplicate
  files or consume persistent storage.

### Changed
- **A confirmed item downloads immediately when no other transfer is waiting.**
  If a download is active or already pending, the same action clearly changes
  to Add to Queue instead.
- **Choosing a destination temporarily folds the popover into the menu bar.**
  DropDrive reopens after the macOS folder panel closes with the analyzed link,
  file selection, and other review choices intact.

## [6.19.0] - Verified transfers and smoother capture

### Added
- **Active transfers keep the Mac awake until their current network attempt
  finishes.** Idle sleep is allowed again during retry delays, pauses, and when
  the queue is idle.
- **Google Drive checksums are verified when available.** Uploaded binary files
  are hashed in bounded chunks after transfer; a mismatched file is removed and
  shown as needing attention instead of being presented as complete. Native
  Google Docs exports, which do not provide MD5, keep their existing path.

### Changed
- **Clipboard capture is consistent across automatic pickup and the Paste
  button.** Both accept URL and text clipboard formats, extract several links,
  remove duplicates, and ignore unrelated clipboard text.
- **The macOS Share menu can send several supported links in one action.** Drive
  resource keys remain intact, and the app receives one compact batch.
- **The global shortcut reports registration failure instead of advertising a
  shortcut already claimed by another app.** Its key combination is now also
  visible in the in-popover settings.

## [6.18.0] - Faster capture from anywhere

### Added
- **Opening DropDrive can pick up supported links from the clipboard.** The
  clipboard is read only on open—never polled in the background—and analysis
  starts without beginning a download.
- **Links can be dropped directly onto the menu-bar icon.** A ready destination
  uses the existing one-step external-link queue; links that need setup or
  sign-in remain in the review field instead of being lost.
- **Control-Option-D opens DropDrive from any app.** If the clipboard contains
  one or more supported links, the same shortcut prepares them for review.

### Changed
- **Every link entry point uses one parser.** Paste, clipboard, Services, and
  menu-bar drops now share source filtering, stable duplicate removal, and
  Drive resource-key preservation.

## [6.17.1] - Remember disconnected destinations

### Fixed
- **A remembered NAS or external-drive destination no longer turns into “None”
  while the volume is disconnected.** DropDrive keeps a non-sensitive path
  fallback beside each security-scoped bookmark, shows the destination as
  unavailable, and reacquires its scope when the volume mounts or the Mac
  wakes. Existing bookmarks migrate automatically the next time they resolve.

## [6.17.0] - Selective, resilient downloads

### Added
- **Choose files inside a Google Drive folder before queueing it.** The review
  card can select individual files or a whole category, and file count, size,
  and required disk space update immediately.
- **Selected folder downloads reuse the analysis manifest.** They start without
  listing the Drive tree a second time, download only the chosen files, and
  leave no empty folders or duplicate cache files behind.
- **Needs Attention replaces Statistics in the primary tab bar.** Recoverable
  network interruptions, disconnected NAS/external destinations, and terminal
  failures are visible in one actionable place.
- **Automatic destinations can be remembered by file type** as well as by
  source. Source-specific rules remain the higher-priority choice.

### Changed
- **Network retry survives longer interruptions.** Backoff now extends through
  five attempts, persists its visible state, and resumes unavailable
  destinations after wake or volume reconnect.
- **Statistics no longer occupy an everyday navigation tab.** Compact lifetime
  totals remain available in Settings → About, stored only on this Mac.
- **Large folder manifests stay memory-only and bounded to 20 hot links.** No
  new on-disk cache is created.
- **Release packaging prefers Developer ID and notarizes automatically when
  credentials are available.** Development-signed updates retain the stable
  Team-ID requirement and production Keychain namespace; ad-hoc publishing is
  still refused.

### Fixed
- **A pasted link can be queued when a writable network destination reports
  unknown free space instead of a literal zero.** Disk capacity is checked
  again during transfer.
- **The Settings experience remains entirely inside the menu-bar popover,**
  including local statistics and updater controls.

## [6.16.3] - Reliable links, one compact surface

### Changed
- **DropDrive stays entirely in the menu bar.** Command-, and reopening the app
  now reveal the inline Settings pane instead of creating a second window.
- **External links are analyzed concurrently.** Browser batches, the Share
  extension, the Services menu, and the phone inbox now share one bounded
  Google Drive and video pipeline.
- **Statistics are true lifetime totals.** The visible Recent list remains
  compact without forgetting older download counts or duplicate identities.
- **The idle status icon is event-driven.** It no longer wakes the app twice a
  second while nothing is downloading.

### Fixed
- **Network volumes that report `0 KB` as an unknown capacity no longer disable
  Add to Queue.** A real missing destination is still blocked, while unknown
  free space is checked again during the download.
- **Phone hand-offs can no longer disappear on a transient failure.** Inputs
  stay in iCloud Drive for a backoff retry; unsupported inputs move to a
  recoverable Rejected folder instead of being deleted.
- **Security-scoped destination access is balanced.** Reopening destination
  menus no longer acquires the same bookmark scope repeatedly.
- **Published updates now require Hardened Runtime and strict signature
  verification** while preserving the existing Team-ID designated requirement
  and production Keychain namespace across versions.
- **Swift concurrency and deprecated AppAuth callback warnings were removed,**
  and small supporting labels are easier to read.

## [6.16.2] - Settings stay in the menu bar

### Fixed
- **Settings no longer opens a separate app window.** The gear now opens a
  compact settings pane inside DropDrive's existing menu-bar panel and returns
  to the previous download pane when pressed again, preserving the app's small,
  all-in-one menu-bar concept.

## [6.16.1] - Safer, faster updates

### Changed
- **The menu-bar window is easier to scan.** Download controls now sit in one
  clear card, the live state is shown as a compact status pill, and recent and
  statistics empty states describe every supported source instead of Drive
  alone.
- **Settings is split into General, Downloads, Appearance, and About tabs.**
  The shorter focused pages replace one long scrolling form.
- **Multi-link analysis now runs up to four checks at once while preserving
  paste order.** The link detector is reused and the paste delay is reduced
  from 120ms to 70ms, so analysis starts and finishes sooner without creating
  extra cache files.

### Fixed
- **Debug builds can no longer make the installed app ask for the Keychain
  password after an update.** Development sessions now use a separate Keychain
  item, while Release builds keep the existing production item and its stable
  access grant.
- **A release can no longer silently fall back to an ad-hoc signature.** The
  packaging script refuses to create a distributable update unless it has a
  timestamped certificate signature and the stable Team-ID requirement. A
  local-only ad-hoc DMG requires an explicit flag and cannot happen by accident.
- **The updater now rejects a package whose designated requirement changes,**
  even if it was signed by the same Apple team. This prevents a manually built
  release from installing successfully and only revealing its changed identity
  when Keychain asks the user for a password after relaunch.
- **Equivalent share links no longer create duplicate queue or history items.**
  YouTube, TikTok, and Instagram links are compared by their canonical content
  identity, ignoring common tracking parameters.
- **Temporary video metadata is removed as soon as a download finishes.** Old
  yt-dlp cache directories are also included in startup cleanup.

## [6.16.0] - Queue-first downloads

### Changed
- **Queue-first confirmation.** A reviewed link now says “Add to queue” and
  does not begin downloading until the queue is explicitly started.
- **Review cards now show a destination preflight.** They surface the selected
  folder, available space, required size when known, a possible name collision,
  and public/private access before an item enters the queue.
- **Settings has its own window.** The menu-bar popover stays focused on quick
  download work.

### Added
- **Paste many links.** Review individual results, select only the wanted
  items, and add them together.
- **Destination favorites, recents, and source rules.** A chosen folder can be
  pinned, reused, or explicitly remembered for a source such as YouTube or
  Google Drive.
- **Faster analysis start.** The paste debounce was reduced from 500ms to
  120ms; cached Drive analyses remain instant.

### Fixed
- **README no longer promises drag-and-drop.** The feature was removed in
  6.15.4, so the documentation now directs people to paste, Share, the Chrome
  extension, or the macOS Service.

## [6.15.5] - Easier link downloads

### Changed
- **The link field is ready as soon as the queue opens.** Paste with Command-V
  without first clicking into the field, and see the supported sources:
  Google Drive, YouTube, TikTok, Facebook, and Instagram.
- **The download destination is clearer.** It is now labelled “Save to” next
  to the selected folder, so it is obvious where the next download will land.

### Fixed
- **Unsupported links now explain what to paste instead.** A Google Photos
  album gets a specific explanation that it is not supported yet; other
  unsupported links list the supported services. Either state can be cleared
  in one click.

## [6.15.4] - Clearer download results

### Fixed
- **Completed multi-file downloads now look like folders.** A folder result was
  mistakenly handed to the file thumbnail generator, which showed a blank
  document icon and made a successful download look broken or extensionless.

### Removed
- **Drag-and-drop links from the empty queue.** The unused drop zone and its
  associated drag handling have been removed; paste links into the link field
  instead.

## [6.15.3] - Video downloads back online

### Changed
- **The update download now says how fast it is going and how long is
  left**, like every other download in the app. A percentage on its own
  cannot tell a slow update from a stuck one — 68 MB on a weak
  connection sits on the same number for minutes — and that is the worst
  thing to leave ambiguous about the one download that replaces the app.

### Fixed
- **YouTube video and MP3 downloads work again.** DropDrive now bundles the
  Deno JavaScript runtime required by current versions of yt-dlp to solve
  YouTube's playback challenges. It runs automatically, so it does not rely
  on Homebrew, Node, or a Terminal configuration.
- **Failed video connections no longer wait indefinitely.** The video engine
  now gives an unresponsive video host 30 seconds before returning its error.
- **Scratch files from cancelled update downloads were never cleaned
  up.** The system writes them next to DropDrive's own temporary files
  and only removes them when a download completes, so every failed check
  left one behind — 232 of them had collected, the oldest three weeks
  old. They are swept with the rest now.

## [6.15.2] - Nothing quietly lost

### Fixed
- **A TikTok link shared from your phone (or the right-click menu)
  failed when TikTok was blocking.** The way around that block was only
  built into the download step, and these two paths read the link
  first — so they gave up before the download ever got a chance. Now
  both take the same detour, and the clip keeps its real caption instead
  of being named "TikTok Embed".
- **A dropped connection was treated as though you had pressed Cancel.**
  Resume data comes back attached to network failures too, not only to
  cancellations, and the engine read its presence alone as "the user
  stopped this". A wifi blip therefore marked the download cancelled,
  threw away the resume data it had just saved, and deleted the
  part-downloaded folder as unwanted — after 38 GB of a 40 GB folder,
  all of it. The automatic retry never ran, because a cancellation is
  not something to retry. Network failures are now told apart from
  cancellations: the partial data stays, the retry runs, and if it
  finally gives up the resume data is kept so Retry continues instead of
  starting over.
- **Restoring the previous session's queue could wedge the app.** The
  restore prompt appears the first time you open the window, and by then
  a link from your phone or the right-click menu may already be
  downloading. Restoring replaced the queue outright, dropping that
  download while the app still believed it was running — after which
  Download All never appeared, Pause and Resume only toggled each other,
  and the menu bar icon span forever. The saved queue is merged in now,
  and a download whose row disappears releases the app either way.
- **Files sharing one name inside a Drive folder overwrote each other.**
  Drive identifies files by id, so one folder can hold three files
  called "invoice.pdf". All three were written to the same path: you got
  one file, the count said three, and nothing reported a problem. Each
  now gets its own name, numbered in a fixed order so a resumed folder
  still recognises what it already has.
- **Sharing a link with a resource key from the Share menu failed.** The
  link was encoded in a way that left its `&` intact, so everything
  after the first one was parsed as a separate parameter and dropped —
  taking `resourcekey` with it, which Drive answers with a 404.
- **A link sent from your phone could vanish without a word.** The inbox
  deletes each file as it consumes it, so when the link could not be
  read — the Mac offline, or a private file while signed out — nothing
  was left and nothing was said. It now tells you it could not use it.
- **Pressing Return on a confirm card threw away the choices made on
  it.** The paste box answered Return by queueing the item straight
  away, and it can't see the card's own state — an MP3 choice, a trim,
  or a typed name were all silently dropped and the download ran as if
  none had been made. The card's Download button is the default action
  now, so Return does exactly what clicking it does.
- **A restored queue of paused downloads couldn't be started at all.**
  "Paused" belongs to a session, not to an item, and the flag holding
  the queue paused doesn't survive a relaunch — so the row's Resume
  button did nothing, "Resume all" never appeared, and neither did
  "Download All", because nothing was waiting. Paused items come back as
  ready, still continuing from where they stopped, and Resume works
  whenever anything is paused.
- **A video you had already downloaded was never recognised as one.**
  The "you've downloaded this before" check read every history entry
  through the Drive link parser, which returns nothing for a TikTok or
  YouTube link — so no video ever matched. Pasting one a second time
  skipped the "Download again?" prompt entirely, and the duplicate guard
  on links arriving from your phone or the right-click menu passed them
  straight through, which is exactly where the same clip is most likely
  to be sent twice. Video links are matched on the link itself now.
- **A video could be saved under the title it had 12 seconds ago.** The
  card appears on a fast title lookup and is refreshed with the one
  yt-dlp resolves; where the two differed, the refresh looked like a
  rename and pinned the file to the older title even though nothing had
  been typed. The name is only treated as yours once you type in it.

## [6.14.1] - Quieter failures

### Fixed
- **A mistyped trim start silently downloaded from 0:00 instead.** Trimming
  a clip only checked the end field for a valid time; a malformed start
  (a typo like "0;30") parsed as nothing, fell back to the beginning of the
  video, and downloaded the wrong section with no warning. Both ends of the
  trim are validated now.
- **Cancelling a video download could leave `.part`/`.ytdl` fragments behind
  in your download folder.** Cleanup matched them against the raw video
  title, but yt-dlp's own filename sanitizing swaps common characters
  (`:`, `?`, `/`, and others — routine in real titles like "Title: Subtitle")
  for lookalikes, so the match silently missed and the fragments were never
  removed. Matched on an alphanumeric skeleton of the name now, unaffected
  by either side's sanitizing.
- **A link already downloaded could be queued and fetched again if it
  arrived from your phone or the right-click "Download with DropDrive"
  menu.** Pasting the same link yourself was already caught by Recent
  Downloads; that same check now covers a phone or Services delivery too.

## [6.15.1] - TikTok MP3 reliability

### Fixed
- **TikTok links can download as MP3 again when the normal post page is
  challenge-gated.** TikTok may respond to the normal downloader with a WAF
  challenge before it exposes the clip. DropDrive now retries its public embed
  page, which supplies the same playable stream, then extracts the MP3 as
  usual. The fallback keeps the title you confirmed and also works with short
  `vm.tiktok.com` share links.
- **A file Drive names without an extension arrived looking corrupted.**
  Drive keeps a file's type in its metadata, so a clip uploaded as "Vo"
  comes back named exactly that. Saved under the bare name the download
  was complete and byte-perfect, but macOS had nothing to identify it
  by: Finder drew the blank "?" document and a double-click handed the
  raw bytes to TextEdit. The extension its declared type implies is now
  added when the name carries none — renaming it yourself keeps the type
  too. The same goes for a name ending in something that only looks like
  an extension, such as the ".549Z" of a timestamp, which macOS treats
  exactly like having none. A name with a real extension is never
  touched. Files already downloaded just need the extension typed on.

## [6.15.0] - Name it before you download it

### Added
- **Rename before downloading.** The confirm card's name is now editable —
  click it (or its pencil) and type. The file lands under that name, a
  folder is created under it, and a video is written to it. The
  extension is never yours to lose: it's shown beside the field rather
  than in it, and a file keeps whatever type it really is. Leaving the
  name alone queues exactly as before.

## [6.14.0] - Noticing updates, and room for the pictures

### Added
- **The menu bar icon marks itself when an update is waiting.** The
  update banner only rewarded someone who already opened the window, and
  nothing suggested opening it. Now the app can say so without needing a
  Notification Centre permission it may never have been granted.
- **Opening the window checks for updates.** The banner can only show
  what a check has found, and nothing triggered one at the moment
  somebody was actually looking at the app.

### Fixed
- **A Mac that never restarts stopped checking for updates.** The check
  ran from the app's initialiser only — "once a day" in practice meant
  "once per launch", and this app launches at login and stays up. It's
  retriggered on a timer and on waking from sleep now.
- **The paste box and the analysis card were offering the same two
  choices at once** — a destination row and a download button each. The
  card owns them while it's on screen, which also gives a row back.
- **The Change button's label was being clipped** by a long destination
  path. The row shows the folder's name; hovering it shows the full path.
- **A profile photo added to your Google account after signing in never
  appeared.** The profile was captured once at sign-in and read from
  local storage forever. It's refreshed in the background now.

### Changed
- **Recent shows two columns instead of three**, at the same window
  width, so a cover grows from 62pt to 100pt. That pane is full of your
  own downloads and they were too small to tell apart.
- **Download progress fills the row** behind the filename rather than
  sitting in a bar of its own underneath. Every number stays.
- Softer corners throughout, and tiles lift slightly under the pointer.

## [6.13.0] - Apple Silicon only, and updates that can't strand you

macOS 27 dropped Intel Macs, so the Intel half of every build served
machines that are frozen on macOS 26 — and nobody using this is on one.
Removing it halves the download. The rest of this release is about making
sure an update can never leave someone with an app that won't open.

### Changed
- **Apple Silicon only.** The download goes from 112 MB to 68 MB; ffmpeg
  alone drops from 152 MB to 62 MB. Requires an M1 Mac or newer.

### Fixed
- **An update that can't run on your Mac is now refused instead of
  installed.** Nothing checked architecture or minimum macOS: the
  checksum matched, the signature verified, so the app would replace
  itself with a build that couldn't launch — and the old copy was already
  deleted by then. Both are checked now, and the version you have keeps
  working.
- **A broken update rolls itself back.** Those checks only catch failures
  that can be anticipated. A build that is perfectly valid and simply
  crashes on launch would take out every copy at once, with the fix
  reachable only through the app that no longer starts. The previous
  version is now kept until the new one has started and stayed running,
  and restored automatically if it doesn't.

### Notes
- The rollback protects updates *after* this one: it's the version being
  replaced that decides how the swap happens, and 6.12.9 doesn't have it.
  This release still installs the old way.

## [6.12.9] - Recent explains itself

### Fixed
- **One missing file could blank out the icons of every file like it.**
  Icons were looked up by path and cached by file type, and macOS answers
  a path that isn't there with the blank generic document — so a single
  moved-away video handed that blank page to every other video for the
  rest of the session. Icons come from the file type directly now, which
  can't be poisoned and doesn't touch the disk.

### Changed
- **Recent says why a tile can't be opened.** A failed download, a
  cancelled one, and a file you moved yourself all drew the same "?"
  square with no explanation, which reads as the app being broken. Each
  now has its own mark and says which it is on hover.
- **Individual entries can be removed** from Recent by right-clicking.
  Clearing the entire history was the only way to get rid of a dead
  entry, which is far too blunt when the rest is worth keeping.

## [6.12.8] - Change the folder from the card itself

### Fixed
- **The download folder looked unchangeable on a video card.** The
  control existed, but as a small line of text above a card that runs
  past 300pt on a video — far enough from where you're looking to
  reasonably conclude it can't be done at that point. The destination and
  its Change button are now on the card, right above Download.
- **An MP3 or trim choice made in the first few seconds silently
  reverted.** A background pass fills in a video's duration and size
  about twelve seconds after the card appears, and rebuilding the card
  reset those selections. The card keeps its state across the refresh
  now.
- That background pass couldn't be cancelled, so it could land on a card
  you'd already moved on from, and it no longer rebuilds the card while
  the folder picker is open on top of it.

## [6.12.7] - The updater, checked properly

Everything here is in the update mechanism itself — the part written in
a hurry and shipped the same day, and the only part that hadn't had a
careful read.

### Fixed
- **An update whose release notes carried no checksum was installed with
  nothing verified at all.** The checksum is optional so a hand-published
  release still works, which meant the one case where the notes are wrong
  or missing was the case with no protection. The downloaded app's
  developer must now match the running copy's, which doesn't depend on
  the notes.
- **The notification's Update button did nothing** when pressing it was
  what launched the app: no check had run, so there was no release to
  install, and it returned in silence.
- **One error removed the Update button for good.** That included "finish
  your download first" — pause the queue and there was no way back to the
  offer. There's a Try again button now.
- **The "don't interrupt a download" guard checked at the wrong moment**,
  20 seconds before the swap that would actually kill it. It re-checks
  immediately before.
- Release notes ending in a colon vanished from the update card.

### Changed
- **Installing an update no longer freezes the window.** The new bundle
  was copied into place on the main thread; it's moved now, off the main
  thread — 92 ms to 0.1 ms on a 201 MB bundle, since the staging folder
  is on the same volume as Applications.

### Internal
- The relaunch helper passes paths as arguments instead of splicing them
  into a shell script containing `rm -rf`. Checked against a bundle
  deliberately named to break it.

## [6.12.6] - An installer window that explains itself

### Changed
- **The installer window now carries the instructions.** They used to
  live only in a help file sitting beside the app, which is easy to miss
  — and someone who meets Gatekeeper's warning having read nothing
  concludes the app is broken, or malware, and stops. The disk image now
  says what the warning is, that it isn't a virus, and what to do, in
  Thai and English, the moment it opens.
- **The Terminal route is listed first** in both the window and the
  guide. It has a copy button and nothing to type, so it's two steps
  where the click-only route through System Settings is three.
- The guide is bilingual, and trimmed to what someone actually needs to
  act on.

## [6.12.5] - See what an update actually changes

### Added
- **"What's new" on the update card.** The card showed the first few
  lines of the release notes and cut off there, with no way to read the
  rest. There's now a small expander with the full notes, on the main
  screen and in Preferences alike.
- Release notes have their Markdown flattened before display — the notes
  come from the changelog, and raw `###` and `**` read as noise in a
  window that doesn't render Markdown.

## [6.12.4] - The last keychain prompt

### Fixed
- **Renewing the signing certificate would have asked for the keychain
  password all over again.** macOS identifies an app by its designated
  requirement, and the default one names the certificate's common name —
  which carries a per-certificate id, so next July's renewal would have
  produced a different identity and a fresh prompt for everyone. The
  requirement is now pinned to the Team ID, which belongs to the Apple
  ID rather than to any one certificate, so renewals no longer change
  the app's identity.

### Notes
- This update asks once, being the build where the identity settles.
  It should be the last time.

## [6.12.3] - Signatures that outlive the certificate

### Fixed
- **Updates would have stopped working in July 2027.** Builds carried
  only a local signing time, not a timestamp countersigned by Apple, so
  the signature would have been considered valid only as long as the
  certificate behind it was — and the updater verifies every download's
  signature before installing. One expiry would have made every future
  update uninstallable, on every machine at once. Builds are now
  timestamped, and the build refuses to produce a DMG without one.

## [6.12.2] - No more keychain prompt on every update

### Fixed
- **Updating asked for the login password every single time.** The app
  was ad-hoc signed, which means macOS identifies it by the hash of its
  binary — so every new build looked like a different application, and
  the keychain refused to hand it the Google session the previous build
  had saved without the password. Builds are now signed with a
  certificate, which keeps the identity the same across versions, so the
  grant carries over.

### Notes
- This update itself still asks once, because it is the build where the
  identity changes. After it, updates are silent.
- Nothing here costs anything: the certificate is the free Apple
  Development one that comes with any Apple ID through Xcode, not the
  paid Developer Program. The app still isn't Gatekeeper-approved, so a
  first manual install still needs the quarantine flag cleared — the
  in-app updater already does that by itself.
- Building on a machine with no certificate still works; it falls back
  to ad-hoc and warns that updates will keep prompting.

## [6.12.1] - The update offer, where you can see it

### Added
- **Available updates now show on the main screen**, not only in
  Preferences → About. The notification's "Update now" button already
  installed in one click, but anyone who missed the notification and
  simply opened the app had no way to know an update existed.

### Fixed
- A launch with no internet burned the whole day's update-check
  allowance. The once-a-day timer now only resets on a check that
  actually reached GitHub.

## [6.12.0] - Updates that install themselves

The last version anyone has to install by hand. From here on DropDrive
notices new releases and updates itself.

### Added
- **Self-updating.** DropDrive checks GitHub Releases once a day, and
  when there's a newer version it shows a notification. One click
  downloads it, verifies it against the SHA-256 published with the
  release, replaces the installed app, and reopens on the new version —
  no dragging to Applications, and no right-click-Open, because the
  updater clears the quarantine flag itself.
- **Preferences → About** gained an update row: check on demand, see
  what's new, and install from there.
- `scripts/release.sh` publishes a version in one command — bumps the
  number, builds the DMG, computes its checksum, and creates the GitHub
  Release the updater reads.

### Notes
- The update check is off until a repository is set in
  `UpdateService.repository`. Versions before 6.12.0 have no working
  update check at all, so friends need this one installed manually.
- Updating never interrupts a download: with the queue running, the
  installer declines and asks you to finish or pause first.
- If replacing the app fails, the working version is put back rather
  than leaving nothing installed.
- Because the app is ad-hoc signed it has no stable code identity, so
  macOS may ask for notification permission again after an update.

## [6.11.0] - A bug hunt, and the engine off the main thread

A second read of the whole codebase, this time looking for things that
were wrong rather than things that were slow.

### Fixed
- **A finished download could show up in Recent greyed out and
  un-openable.** The gallery caches "is this file still on disk?"
  answers. A tile drawn while the file was still downloading started a
  check that answered "missing"; the download then finished and cleared
  the cache, and that stale answer landed *afterwards* — writing
  "missing" back into the empty cache with nothing able to ask again.
  In-flight checks are now abandoned along with the cached answers.
- **Pasting a link that's already in the queue said nothing.** Clearing
  the text field re-triggers analysis, which resets the card state — and
  it was done *after* the "Already in queue" state was set, wiping it in
  the same turn. The card never appeared; the link just vanished.
- **"Download Again" queued the item but didn't start it,** unlike every
  other confirm button, so nothing happened until the user found
  "Download All".
- **Downloading a single file could overwrite an unrelated file of the
  same name** in the destination folder, destroying it. Single files now
  land beside it as "name (1)", the way folder downloads already did.
  (Inside a folder the plain name is kept on purpose — that's how
  resuming knows what it already has.)
- **Cancelling or removing one queue item could kill a different
  download.** Removing an item swept away *every* `.dddownload` staging
  file in the destination, including the one a still-running multi-part
  download was writing into — throwing away everything it had
  transferred. It now removes only its own.
- **Pausing in the instant before a connection opened was ignored** and
  the transfer ran to completion: cancellation could arrive before there
  was a task to cancel, and nothing recorded that it had.
- **The "N today" count in the header froze at yesterday's number** if
  the app sat idle across midnight.
- Quick Look could be handed an empty file list.
- More English-only strings translated: the notification titles and
  their buttons, the folder picker's own panel, and the Preferences
  bandwidth/folder controls.

### Changed
- **The download engine no longer runs on the main thread.** Creating a
  folder's directory tree, statting every planned file, sweeping stale
  staging files, truncating and renaming — all of it was main-actor
  isolated by the project's default, so the window couldn't redraw while
  any of it ran. Measured mid-download, the main thread now stalls at
  most ~4 ms.

### Internal
- Removed three unused declarations, one of which was an English-only
  string that would eventually have shown up in the UI.
- The offline harness gained coverage for overwrite protection and a
  main-thread responsiveness check.

## [6.10.0] - A pass over everything for speed

No new features — a sweep through the whole codebase for work the app was
doing that it didn't need to do.

### Changed
- **Folder scanning walks the tree in parallel.** Both the analysis card
  and the download plan listed one folder, waited for the answer, then
  listed the next, so a tree cost the sum of every round trip in it.
  Sibling folders are now listed a level at a time, six at once — a
  17-folder tree scans in 0.65s where it used to take 2.2s, with the same
  file count, byte total, and category breakdown coming out. The listing
  and its JSON decoding also moved off the main thread, so a folder with
  thousands of files no longer stalls the window while it's read.
  Folders that reach themselves through a shortcut now stop instead of
  looping.
- **Big files get more connections.** Drive throttles each connection
  regardless of the link's real speed, so throughput scales with the
  number of streams: files over 200 MB now use 6 ranged connections and
  files over 1 GB use 8, instead of a flat 4.
- **The "does this server do ranged requests?" probe runs once per host**
  rather than once per large file — a folder of big files was spending a
  wasted round trip apiece to re-learn the same answer.
- **A folder download checks each planned file's existence once**, not
  three times, before it starts.
- **Menu bar and phone-inbox timers have slack**, so an idle app lets
  macOS coalesce its wake-ups instead of forcing its own twice a second.
  The iCloud inbox scan also moved off the main thread.

### Fixed
- The remaining-time readout was English-only; it's bilingual now.

### Internal
- Formatters, file-type icons, and file-existence checks are cached
  instead of being rebuilt inside SwiftUI bodies that redraw several
  times a second during a download; queue and history totals are
  computed once per change rather than per redraw. The thumbnail cache
  is now bounded.

## [6.9.3] - Confirmations you can actually click

Found by driving the real app rather than reading the code.

### Fixed
- **Confirmation dialogs ignored every click.** The restore-queue prompt
  and the disk-space warning were SwiftUI alerts attached to the menu bar
  popover, and such an alert only accepts input while its window is key —
  which for an agent app is rarely true. The dialog rendered, the buttons
  highlighted, and nothing happened. Both are real `NSAlert` panels now,
  which bring the app forward and run their own modal session.
- **The restore prompt no longer ambushes you at login.** It fired during
  app launch, so with "launch at login" enabled it would interrupt every
  boot. It's asked the first time the window is opened instead.
- **Stale LaunchServices registrations** from old build folders were
  hijacking the `dropdrive://` scheme, so deep links (and by extension
  the Share extension and the phone inbox) silently went nowhere. The
  installed app is now the only registered copy.

## [6.9.2] - Data races cleared out

A full pass with strict concurrency checking turned on, which surfaced
20+ isolation problems the normal build says nothing about.

### Fixed
- **The path of a finished video download was written from one thread and
  read from another.** yt-dlp's output is parsed on the pipe-reader
  thread, and the discovered file path lived in a plain captured
  variable — a real race, and losing that write means a completed
  download reporting it can't find its own file. It's held in a
  lock-protected box now.
- **Helpers used from download threads claimed to be main-actor
  isolated.** BandwidthLimiter (which deliberately sleeps its caller),
  the yt-dlp output collector, the progress rate smoother, and the byte
  counter all do their own locking but were annotated as if they only
  ran on the main thread — the opposite of how they're used, and
  BandwidthLimiter would have frozen the UI had anything called it from
  the main thread. All are explicitly `nonisolated` now.
- **Startup temp cleanup is genuinely off the main thread**, so sweeping
  gigabytes of abandoned scratch can't stall the UI.
- **Theme changes, the auth-state handoff, and the analysis cache** no
  longer cross isolation boundaries unchecked.
- **A negative speed could flash on screen** for one sample after a
  parallel download handed its bytes back during fallback.
- **A single-file download killed mid-flight left its `.dddownload`
  staging file** in the user's folder; it's cleaned up now.

## [6.9.1] - YouTube files that actually open, and a folder picker that stays put

### Fixed
- **YouTube downloads produced files a Mac can't open.** Left to pick the
  best quality, yt-dlp chose AV1 video with Opus audio in a `.webm`
  container — rejected by QuickTime, Finder preview, and most editing
  software, so it looked like the download had failed. Video downloads now
  ask for H.264 + AAC in MP4, verified playable via AVFoundation. A new
  Preferences toggle ("Keep videos playable on Mac") turns this off for
  anyone who would rather have 4K, since resolutions above 1080p are
  AV1-only on YouTube; either way the container is MP4, never webm.
- **The destination folder couldn't be changed once a link was
  analyzed.** Opening the folder chooser takes key focus, and the popover
  dismisses the moment that happens — taking the analysis card with it,
  so the click appeared to do nothing. The popover is now pinned while
  the chooser is up, and the app comes forward so the panel can't open
  behind another window.

## [6.9.0] - Smoother readouts, honest progress, lighter UI

The rest of the code-review findings.

### Fixed
- **Video download speed no longer flickers.** yt-dlp reports the
  instantaneous rate of whichever fragment it is on, which swings hard as
  fragments start and finish; that raw number went straight to the
  screen. It is now smoothed with the same weighting the Drive path uses.
- **Progress can no longer sail past 100%.** When a parallel download
  failed and fell back to a single stream, the bytes the failed attempt
  had already reported stayed in the total and were then counted again.
  The fallback now subtracts them first.
- **The Recent gallery no longer hits the disk while drawing.** Every
  tile ran `fileExists` (and a directory check) inside its body, which
  SwiftUI re-runs freely — on the main thread. Those answers come from a
  small cache now, refreshed off the main actor and invalidated whenever
  a download finishes.
- **The link-analysis cache is bounded** at 100 entries, so a long
  session can't accumulate every folder breakdown ever scanned.

## [6.8.1] - Two corruption risks in the new parallel writer

Found by reviewing 6.8.0's own changes — both are silent-corruption
paths, neither would have announced itself.

### Fixed
- **A download killed mid-flight could be mistaken for a finished one.**
  Writing ranges straight to the final filename meant a force quit,
  crash, or power loss left a full-size file with holes in it — and the
  folder-resume check treats "file exists" as "file is done", so it would
  skip that file forever. Ranges now land in a sibling `.dddownload`
  staging file that is renamed into place only after every range
  completes; the real name never exists in a half-written state. Renaming
  within a volume is free, so peak disk usage is unchanged. Stale
  `.dddownload` files are cleared when a folder download resumes.
- **A short range was written as zeros.** A server may legally answer a
  range request with less data than asked for; that tail was left as the
  zeros the sparse file was created with, in a file that otherwise looked
  complete. Each range now verifies it received exactly the bytes it
  asked for and fails over to the single-stream path otherwise.

## [6.8.0] - Parallel downloads no longer cost extra disk space

The whole point of this app is downloading straight from Drive instead
of the zip-then-unpack round trip that needs room for two copies. The
multi-part downloader had quietly reintroduced exactly that: each range
landed in its own temp file, and the finished file was assembled from
them, so a download briefly needed about twice the file's size.

### Changed
- **Ranges now stream directly into their own region of the destination
  file.** The file is created at its final size up front (sparse on
  APFS, so blocks are consumed only as bytes arrive) and each connection
  seeks to its range and writes there. No temp copies, and no assembly
  pass re-reading and re-writing every byte at the end — so downloads
  also finish sooner. Peak disk usage is now exactly the file's size.
  Verified: a 38 MB file fetched over 4 concurrent ranges is
  byte-identical (matching sha256) to a plain download, with zero temp
  directories created and disk usage growing from 9 MB mid-flight to
  38 MB at completion.
- The free-space check drops its 2x multiplier accordingly and now asks
  only for the download's size plus headroom.

## [6.7.0] - Disk space: stop filling it, warn before it's a problem, say so when it happens

Diagnosed from a real incident: a download died mid-flight and the disk
turned out to be full, with no clue from the app as to why.

### Fixed
- **Abandoned downloads no longer strand gigabytes of scratch files.**
  Multi-part downloads stage byte ranges in temp directories that are
  only cleaned up on the way out — which never happens when the app is
  killed mid-download. Found 20 leftover directories holding 14 GB on the
  reporting machine, which is what filled the disk. Startup now sweeps
  any `DropDrive-*` scratch older than an hour (younger ones may belong
  to a download still in flight).
- **A multi-part download no longer needs double the file's size.** Each
  staged part is deleted the moment it's appended to the assembled file,
  instead of all parts being held until the end.
- **"Something went wrong" replaced with the actual reason.** A disk that
  fills mid-download now says so, as do rate limiting (429), Drive
  outages (5xx), timeouts, dropped connections, and unwritable
  destinations — each with what to do next, in Thai and English.

### Changed
- **The free-space check now blocks instead of warning, and catches the
  cases it used to miss.** It accounts for the ~2x peak a parallel
  download needs while assembling, and no longer skips downloads of
  unknown size (every video link, since the card is built from oEmbed
  data that carries no size — the exact path that filled the disk). The
  alert offers to open the destination folder so space can be cleared.

## [6.6.2] - Video downloads reuse the analysis work

### Changed
- **A video download no longer re-extracts what analysis already
  resolved.** yt-dlp spends most of a download resolving formats, and it
  was doing that twice — once for the card, once on Download. The info
  from analysis is now cached for 30 minutes and passed back via
  `--load-info-json`, measured at 36.2s -> 18.4s for the same file.
  Signed media URLs expire, so a rejected cache silently falls back to a
  full extraction, and a missing cache just takes the normal path.

## [6.6.1] - Video links analyze in under a second

### Fixed
- **Pasting a video link took ~13 seconds to show its card.** All of it
  was yt-dlp resolving every available format just to read a title.
  Analysis now asks the platform's oEmbed endpoint first (measured 0.35s
  for YouTube, 0.56s for TikTok, versus 12.7s for yt-dlp), which returns
  the title, uploader, and thumbnail the card needs. yt-dlp still runs,
  but in the background, and only swaps in once it has the duration and
  size — by which time the card has long been on screen and usable.
  Instagram has no open oEmbed, so it still falls back to yt-dlp.

## [6.6.0] - Bottom tabs, shorter window

### Changed
- **Layout overhaul.** The left icon rail is gone. Menu tabs (Queue,
  Recent, Statistics, Preferences) moved to a horizontal bar along the
  bottom — icon-only except the selected tab, which shows its label in a
  pill. A slim top bar keeps the logo, wordmark, status, and account.
  With the tall rail gone, and the idle-queue placeholder text removed,
  the window hugs its content far more closely.
- **Account moved to the top-right corner** as a small avatar (out of
  the old rail).
- **Quit moved to the menu bar icon** — right-click (or control-click)
  the icon for a Quit menu; the in-app power button is gone.
- **Menu bar icon is the app icon** in full color when idle, turning
  into a progress ring while downloading, a checkmark on finish, and a
  warning triangle on failure.

### Under the hood
- Migrated from SwiftUI `MenuBarExtra` to a manual `NSStatusItem` +
  `NSPopover` (`StatusItemController`) so the icon can handle left-click
  (popover) and right-click (menu) separately.

## [6.5.0] - Recent is now a thumbnail gallery

### Added
- **The Recent pane is a gallery.** Real Quick Look thumbnails for files
  (video frames, image contents, PDF pages), a 2×2 "album cover" collage
  of the actual files inside each downloaded folder with a count badge,
  and type/status placeholders (MP3 note, dimmed tile for moved files).
- **Drill into a folder** — click a folder tile to browse the files it
  contains as their own gallery, with a back button.
- **Quick Look and open** — hover a tile for eye/open/reveal buttons,
  double-click to open (or drill into a folder), right-click for the
  full menu. A list/gallery toggle keeps the old text rows one click
  away.

## [6.4.0] - Send links from your phone, and a right-click Service

### Added
- **Send from phone.** An iOS Shortcut (share sheet) saves links into
  the DropDrive folder in iCloud Drive; the Mac watches it, queues every
  link automatically (videos included), notifies, and starts downloading
  if idle. Toggle in Preferences.
- **"Download with DropDrive" in the right-click menu.** Select any link
  text in any app → Services → done. Plain NSServices registration — no
  app extension.

## [6.3.0] - Thumbnails and clip trimming on the video card

### Added
- **The video confirm card shows the real thumbnail** with a duration
  badge, so you know it's the right clip before downloading.
- **Trim to a section.** Tick "ตัดเฉพาะช่วง", type start–end times
  (0:10 – 1:30 style, hours supported), and only that section downloads
  — cut at keyframes for accuracy, saved with a "(clip)" suffix so it
  never collides with (or skips because of) the full video. Works for
  MP3 extraction too.

## [6.2.0] - Instagram links

### Added
- **Instagram support** — public posts and reels download through the
  same video pipeline (video or MP3). Login-walled or private content
  shows yt-dlp's error on the failed card rather than pretending to work.

## [6.1.0] - MP3 extraction for video links

### Added
- **Download as MP3.** The confirm card for a TikTok/YouTube/Facebook
  link gained a Video / MP3 segmented switch — MP3 extracts the audio
  through the bundled ffmpeg at best VBR quality, shows a "Converting to
  MP3…" stage, and lands the .mp3 in the chosen folder. MP3 queue rows
  carry a music-note icon; the choice persists with the queue item.

## [6.0.0] - Video downloads: TikTok, YouTube, Facebook

### Added
- **Paste a TikTok / YouTube / Facebook link and download the video** —
  TikTok comes out watermark-free (the same source the "no watermark"
  sites serve), YouTube merges best video+audio up to full quality, and
  it all flows through the existing queue: analysis card with
  title/uploader/size, confirm to download, live progress with speed,
  pause/resume (yt-dlp continues its own .part files), cancel cleans up
  partials, history and notifications included.
- Powered by bundled universal (Intel + Apple Silicon) builds of
  **yt-dlp** and **ffmpeg**, fetched by `scripts/fetch-video-tools.sh`
  (binaries are gitignored; run the script once per checkout). This
  grows the app by ~190 MB uncompressed — the price of full-quality
  YouTube merges.

### Notes
- Downloading from these platforms is against their terms of service in
  most cases; DropDrive is a personal tool — use it for your own stuff.

## [5.10.0] - Theme choice and a disk space check

### Added
- **Theme picker in Preferences: System / Light / Dark.** The whole
  popover palette (canvas, cards, rail, borders, accent) now resolves
  through `AppTheme`, with a warm-dark counterpart to the light design
  and a brighter accent blue for dark. System mode follows macOS
  appearance changes live.
- **Free-space check before starting a download.** If the queue's known
  size (plus 200 MB headroom) won't fit on the destination volume, a
  warning shows the needed vs. available sizes, with an explicit
  "Download anyway" escape hatch. Sizes Drive didn't report count as
  zero — a missed warning is preferred over a false one.

## [5.9.0] - Smarter downloads: auto-retry, live menu bar progress, clean cancels

### Added
- **Network drops retry themselves.** A download that fails with a network
  error now retries automatically up to three times (5s → 15s → 45s
  backoff), continuing from resume data instead of starting over. The
  active card shows the countdown; cancel and pause work during the wait.
- **The menu bar icon shows live progress.** While downloading, the tray
  icon becomes a progress ring (template-drawn, so it matches light and
  dark menu bars); the queue finishing flashes a checkmark for two
  seconds, and a failed item waiting for retry shows a warning triangle.
- **Pause/Resume per item.** The active download card gained a Pause
  button next to Cancel, and a paused row shows a Resume pill.
- **First-run welcome.** A one-time three-step walkthrough (menu bar
  location, paste a link, pick a folder) shown in place of the popover —
  mostly so friends don't think the app "didn't open".

### Changed
- **Cancelling now leaves nothing behind.** Cancelling an active folder
  download — or removing an unfinished item with ✕ — deletes the
  partially-downloaded folder from disk. Matching is by the
  `.dropdrive-inprogress` marker (never by name), so only folders the
  app itself created mid-download can ever be removed.

## [5.8.0] - DropDrive now lives in the menu bar

### Changed
- **DropDrive is now a menu-bar-only app.** There is no Dock icon and no
  separate main window — clicking the tray icon in the menu bar opens the
  whole app in a single popover window. `LSUIElement` is set, the old
  `WindowGroup`/`Settings` scenes are gone, and with them the entire
  family of duplicate-main-window workarounds in the app delegate.
- **New icon-rail layout.** A narrow rail on the left of the popover
  switches between four panes: Queue (paste field, link analysis, and the
  live download queue), Recent (searchable history), Statistics, and
  Preferences. The rail shows a badge with the number of active/pending
  downloads, and Quit moved to a power button at the bottom of the rail.
- **Preferences moved in-window.** The standalone Settings window is gone;
  Preferences is a rail pane now, with an About section (version + blurb)
  replacing the old About panel. Statistics got its own pane instead of
  living inside Preferences.
- **Notifications' "Open DropDrive" action** now just activates the app —
  there is no window to order front any more; the menu bar icon is always
  available.

### Removed
- `ContentView`, `StatusBarView`, and `WindowAccessor` — all only existed
  to serve the old main window.

## [5.7.1] - Every queued file was sharing one destination

### Fixed
- **Pasting a second link while one was downloading sent it to the same
  folder as the first, no matter what "Save to" showed.** `QueueItem` had
  no destination of its own — `processQueueIfNeeded` read the view model's
  single `selectedDestinationURL` at the moment a download *started*, not
  when it was queued. Changing "Save to" while anything was still pending
  silently moved every queued item's destination, including files queued
  before the change. `QueueItem` now captures `destinationURL` at enqueue
  time; each item downloads to the folder that was selected when it was
  added, and changing "Save to" only affects links pasted after that.
- **"Connect" stayed up after a successful sign-in on a private file.**
  `signInWithGoogle()` retried the pending link by assigning it back to
  `driveLink`, relying on that property's `didSet` to re-trigger analysis.
  But the link never left the text field, so the assignment was a no-op,
  and `didSet` deliberately ignores no-op writes. Analysis never re-ran;
  only quitting and re-pasting worked, because that's a real change.
  `scheduleAnalysis()` is now called explicitly after sign-in.

### Changed
- **Folder downloads run several files at once instead of one at a time.**
  A folder of many small files spent most of its wall-clock time on
  per-file round-trip latency rather than transfer — paid once per file,
  serially. Up to 5 files now download concurrently (each still eligible
  for its own multi-part split past 20 MB), which should meaningfully
  speed up folders with many files. Progress now reflects whichever file
  most recently reported bytes rather than one strictly-ordered name, since
  several are in flight at once.
- **Removed the public/private lock-or-globe badge** from the queue rows
  and the duplicate-download prompt — every file the reporting user
  downloads is private, so it added nothing per-row. The "sign in to access
  this item" lock icon is unrelated and stays; it's the only thing telling
  the user *why* a Connect button appeared.
- **Removed the Chrome extension** (`browser-extension/`). Pasting a link
  directly, or using the macOS Share menu (`DropDriveShare.appex`, which
  hands off through the same `dropdrive://` URL scheme independently of
  the extension), remain.

## [5.7.0] - The DMG could never have run on an Intel Mac

Reported from the first real attempt to hand the app to someone else:
"can't open it, ran the Terminal command, nothing happened."

### Fixed
- **Every DMG so far was Apple-Silicon-only.** `xcodebuild` picks the first
  matching destination when given none, which on this machine is
  `arch:arm64` — so the shipped binary was `arm64` alone and could not
  launch on an Intel Mac at all, no matter how many times the quarantine
  command was run. `scripts/build-dmg.sh` now builds with
  `-destination 'generic/platform=macOS'` and explicit
  `ARCHS="arm64 x86_64"`, and refuses to package anything that isn't
  universal rather than shipping the same silent failure again. Verified:
  every Mach-O in the bundle, including the Share extension, is now
  `x86_64 arm64`.
- **The quarantine command didn't reach nested code.** The note said
  `xattr -d com.apple.quarantine …`, which only clears the bundle root; the
  app embeds a Share extension that carries its own quarantine flag. It's
  now `xattr -cr …` — recursive, and quiet when an attribute isn't present
  instead of printing errors at someone following instructions.

### Known limitation
The minimum is still macOS 14. `@Observable` (three files) and two-argument
`onChange` require it; dropping to 13 means converting those, and dropping
to 11 additionally costs `MenuBarExtra` and drag-to-reorder, which are
13-only.

## [5.6.1] - Controls that look clickable now are

### Fixed
- **The queue's ✕ did nothing.** A cancelled row drew an
  `xmark.circle.fill` status icon — the standard macOS remove glyph — but
  it was only ever an icon; Remove lived exclusively in the right-click
  menu. Every row that isn't mid-download now has a real remove button,
  and the cancelled status icon is `slash.circle` so it stops
  impersonating a control. Same class of bug as reveal-in-Finder being
  context-menu-only in 5.5.0.
- **The Chrome button died silently after an extension reload.** Reloading
  or updating the extension leaves the previously-injected content script
  running in open Drive tabs with a dead `chrome.runtime`, so clicking
  threw an uncaught "Extension context invalidated" — visible only on
  `chrome://extensions`, which just looked like a dead button. It now
  detects the stale context and shows "DropDrive was updated — reload this
  page to use it".
- **Toasts kept their first message.** `showToast()` only set its text when
  creating the element, so a reused toast showed whatever it said first.

### Changed
- The Chrome extension's manifest version tracks the app again (it sat at
  5.4.4 while the app moved through 5.4.5 → 5.6.0; it was simply never
  bumped alongside it).

### Verified
The remove button was exercised on a real queue row and removes as
expected. The reloaded extension injects its button into a Thai-locale
Drive and hands the selection off to the app.

### Not verified
The stale-extension toast. It only fires when a content script outlives an
extension reload, and the reload that would have triggered it was done
alongside a page refresh — the path it guards is still unobserved.

## [5.6.0] - Sign-in actually works on a free build

"It asks me to connect while already connected" was two separate faults
stacked on top of each other, and neither was in the app's logic.

### Fixed
- **Google sign-in could never complete.** GoogleSignIn stores its session
  in the *data-protection* keychain (it sets
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, which forces
  `kSecUseDataProtectionKeychain`). On macOS that keychain requires an
  `application-identifier` entitlement that only a real Apple Team
  signature provides, so an ad-hoc signed build failed every write with
  `errSecMissingEntitlement` (-34018); GID surfaced it as "keychain
  error" (-2) the instant the OAuth redirect succeeded, leaving
  `currentUser` nil forever. Confirmed with an ad-hoc test binary: -34018
  from the data-protection keychain, `errSecSuccess` from the file-based
  one. GID exposes no public way to swap its store, so `LoginManager` now
  drives **AppAuth + GTMAppAuth directly** — both already linked — and asks
  for `.useFileBasedKeychain`, which needs no entitlement. Verified live:
  sign-in completes, the session survives quit/relaunch *and* a rebuild
  with a fresh ad-hoc signature, and the Drive API authenticates.
- **The account chip claimed a session that wasn't there.**
  `restoreSavedAccount()` fell back to a UserDefaults-cached account even
  when no session could be restored, so the header showed "connected"
  while every private-file analysis still demanded sign-in. It now only
  reports an account when one genuinely restores, and clears the stale
  cache otherwise.

### Changed
- **The ad-hoc build is no longer sandboxed.** A sandboxed app can't reach
  the keychain at all without `keychain-access-groups`, which macOS only
  honours behind a real Team prefix; self-assigning one (with or without
  `com.apple.application-identifier`) makes launchd refuse to spawn the
  app. Re-signing with the sandbox back on reproduced the failure — the
  chip went empty because the stored session couldn't be read. Both
  changes are needed together. This build ships as a DMG rather than
  through the App Store, where the sandbox is optional; the Team-signed
  build keeps its sandbox, and the Share extension stays sandboxed.

### Note
Google Cloud's consent screen for this project was also switched from
Internal to External/in-production — while it was Internal, any account
outside the owning Workspace was rejected with `403 org_internal` before
the keychain ever came into play.

## [5.5.0] - New identity: icon, wordmark, and a tidier UI

A visual pass. New app icon everywhere, a proper logo-plus-wordmark
header, a main window that actually fits its content, a visible
reveal-in-Finder button, and a simplified menu bar.

### Added
- **New app icon** across every size (16→1024). The old generic tray
  glyph is replaced by a document-dropping-into-a-tray mark, extracted
  pixel-exact from the source render and masked to a transparent
  squircle.
- **Logo + two-color wordmark header.** The main window (and the menu
  bar) now show the app logo above "DropDrive" with `Drop` in the
  primary label color and `Drive` in blue. `Drop` uses `.primary` so it
  stays legible in both light and dark mode rather than a fixed dark hex.
- **Visible reveal button in Recent Downloads.** Revealing a finished
  download in Finder was previously buried in the right-click menu only.
  Each row with a file on disk now shows an always-visible folder button
  (accent on hover); the context menu still works too.

### Changed
- **Menu bar redesigned to a lighter layout.** Dropped the full queue
  list that made it feel like a second copy of the app. It now shows a
  paste-link field (submits and brings the window forward), a single
  status line (live progress with pause/cancel while downloading, or a
  short "N downloads today" / "Ready" summary when idle), and Open
  DropDrive / Preferences buttons.
- **Main window fits its content.** It previously opened ~900pt wide with
  the 360pt content stranded in the middle: `.frame(maxWidth:)` only
  bounds the view, and `.windowResizability(.automatic)` let the window
  ignore it. Now `.contentSize` makes the window hug the content's ideal
  frame, opening at a compact ~460×570.

### Packaging
- The ad-hoc DMG build is scripted (`scripts/build-dmg.sh`) with a
  composed Finder window (flat background, arrow, tight size) and bundles
  an in-DMG "If DropDrive won't open" note for the one-time
  `xattr -d com.apple.quarantine` step. The script cleans up its own
  build scratch so duplicate `.app` copies stop accumulating in Spotlight.

## [5.4.4] - Three real bugs found from live use, not testing

Reported directly from using the app, not found by QA: a redundant login
prompt despite already being signed in, a new hidden window piling up on
every Chrome deep link, and occasional corrupted downloads.

### Fixed
- **Redundant login prompt.** `cachedAccessTokenIfAvailable()` only checked
  `GIDSignIn.sharedInstance.currentUser`, which can still be `nil`
  immediately after launch — restoring a previous session happens
  asynchronously and separately (`restoreLogin()`, triggered from the
  UI). A deep link's analysis could race ahead of that restore and wrongly
  conclude "not signed in" even though a valid session existed. Now
  attempts the same silent restore itself instead of assuming another,
  unsynchronized call already finished first.
- **A new hidden window piling up, both on plain launch and on every Chrome
  deep link.** Confirmed by direct reproduction (not just reasoned about):
  a clean launch alone could produce 2+ main windows with zero user
  interaction, and each incoming `dropdrive://` link while already running
  added another. `.onOpenURL` was removed — incoming URLs now go through
  `NSApplicationDelegate.application(_:open:)` once, directly against the
  shared view model — but SwiftUI's `WindowGroup` still independently
  spawned extra window instances regardless, so this is enforced directly:
  the app delegate now sweeps for windows titled "DropDrive" (SwiftUI sets
  this synchronously and consistently, unlike `WindowAccessor`'s own
  `frameAutosaveName` tagging, which a live repro showed losing a race and
  silently missing 2 of 3 real duplicates) after launch, after every
  incoming URL, and whenever any window becomes main, closing every extra
  down to one.
- **Occasional corrupted downloads.** The multi-threaded ranged-download
  path probes once for `Range` header support before starting, but never
  re-checked that each of the 4 concurrent part-requests actually got back
  `206 Partial Content` rather than `200` with the *entire* file — some
  CDNs/caches honor `Range` inconsistently, especially once a URL is
  already cached. A `200` response for a "part" silently meant that part
  file held the whole file, and concatenating it with the other three
  produced a garbled, oversized result with no error at any point. Each
  part now requires exactly `206`; anything else fails that part and falls
  back to the existing reliable single-stream path instead of writing a
  corrupted file.

## [5.4.2] - Beta label

### Changed
- The status bar and About panel read "Dev" — a leftover from before this
  release had been verified against a real Chrome/Drive workflow. Now
  that it has (see 5.4.0/5.4.1), relabeled to "Beta".

## [5.4.1] - Chrome-only

### Removed
- Dropped the Safari extension entirely. Its Xcode project only ever
  referenced `background.js` and `manifest.json` from the shared Chrome
  source — `content.js` (the toolbar-button and context-menu injection
  logic that's the actual point of the extension) and the icon images
  `manifest.json` points at were never wired in, so Safari never actually
  had a working "Download with DropDrive" button or menu entry, only the
  inert message-handling half. Rather than fix and re-verify a second
  browser target, DropDrive is Chrome-only going forward, matching the
  scope this integration was always primarily built and tested for.

## [5.4.0] - Chrome integration verified end-to-end

### Fixed
- Chrome extension couldn't launch DropDrive at all in practice: none of the
  Chrome-side selector fixes from 5.3.0 had ever been checked against a real,
  live Drive session. Live testing this release found and fixed two real
  selector bugs (the selection toolbar's actual ARIA role is `region`, not
  `toolbar`; `data-tooltip`/`aria-label` values are localized, not just the
  visible text — confirmed against a Thai-locale account), a drag-and-drop
  return-value bug in the queue reorder handler, and a macOS 26.0-only
  `dropDestination` overload the compiler was silently picking over the
  macOS 13+ one available at this app's actual deployment target.
- Auth flow: opening a private file via the Chrome extension before signing
  in previously left the user stuck after login with no next step. The
  pending link is now stored and automatically retried once sign-in
  succeeds, with no need to re-select the file in Chrome.
- Chrome's own item context menu renders in two passes — a quick partial
  menu, then a fuller one moments later — and the second pass was
  reshuffling the DOM in a way that stranded the injected "DropDrive" entry
  at the top of the menu instead of directly under "Download". Injection is
  now re-entrant (re-checked on every later menu mutation, not just once)
  and anchors off the last matching "Download" node rather than the first.
- Lowered `MACOSX_DEPLOYMENT_TARGET` from the Xcode-default `26.5` down to
  `14.0`, the actual floor set by `@Observable`/`Observation` usage — this
  had never been revisited since project creation.

### Changed
- Chrome toolbar button redesigned: a small solid-blue pill (cloud-down
  glyph + "DropDrive" label) instead of a bare gray icon that read too
  close to Drive's own Download button. Sized off a two-layer box — an
  outer box matching the reference Download button's height for row
  alignment, an inner pill for the small visible chip — so it lines up with
  neighboring icons regardless of how Drive's own row aligns its children.

### Verified (real, live, end-to-end — not simulated)
This is the first release where the full Chrome → DropDrive workflow was
actually exercised against the live drive.google.com UI rather than reasoned
about from documented DOM conventions:
- Selecting a real private file and clicking the Chrome toolbar button sends
  it to DropDrive via `dropdrive://download?url=...`.
- The app receives the link, detects it needs Google sign-in, and — after
  signing in — automatically queues the file without any manual re-entry.
- A real 1.95 GB file downloaded to completion; the resulting file was
  verified on disk (correct size, valid, unstructured video data).
- "Reveal in Finder" opened Finder with the completed file selected.
- The right-click "DropDrive" entry appears directly under Drive's own
  "Download" item in the file context menu.

### Known gaps
- Multiple-file selection, folder selection, and the Safari extension were
  not re-verified this round (only a single private file was exercised
  through the full live flow above).
- Still signed with a local "Apple Development" certificate, not notarized
  — same standing limitation since 4.0.0. A machine building this needs an
  Apple ID added under Xcode's own Accounts settings for
  `-allowProvisioningUpdates` to register the device automatically;
  without one, the signed build fails outright with "No Accounts" rather
  than a signing error.

## [5.3.0] - Final Chrome integration sprint

### Changed
- Rewrote the Chrome extension's selection model. It previously only
  detected a Drive item from the page URL (`/file/.../` or `/folders/...`),
  which meant it did nothing on Drive's actual file-listing/selection UI —
  the primary way people use Drive. It now reads the real selection
  (`[aria-selected="true"][data-id]`), works in both List and Grid view,
  and supports single, multiple, folder, and mixed selections, sent to
  DropDrive in the order they appear in Drive's own list/grid.
- Toolbar integration: instead of an always-injected custom-styled button,
  DropDrive's icon is now inserted directly next to Drive's own Download
  button (matched primarily via `data-tooltip`/`aria-label="Download"`),
  sized to match, with a "Download with DropDrive" tooltip. It appears and
  disappears with Drive's own Download button rather than being always
  present.
- Context menu integration: previously only used `chrome.contextMenus`,
  which only affects the browser's native right-click menu — Google Drive
  renders its own custom right-click menu and suppresses the native one
  entirely, so that never actually appeared on a file/folder row. Now also
  detects Drive's own menu opening and inserts a "DropDrive" item directly
  below "Download" inside it, cloned from Drive's own item so it matches
  styling automatically.
- Added a "✓ Sent to DropDrive" toast on send, single-instance (re-sending
  resets its timer rather than stacking a second one).
- `dropdrive://download?url=` now accepts the `url` parameter repeated
  once per selected item (`?url=A&url=B`) for a multi-selection, still the
  one endpoint — not a new one. Minimal corresponding change on the
  DropDrive app side: multi-item deep links are analyzed and queued in
  order, silently (no per-item duplicate-redownload prompt interrupting a
  batch).
- Added real extension icons (16/48/128), derived from DropDrive's own app
  icon, replacing the missing-icon manifest gap.
- Simplified the MutationObserver-driven re-sync logic (the previous
  version's "is this mutation relevant" filtering was dead code — it always
  evaluated true — removed rather than fixed in place, since the
  requestAnimationFrame debounce already bounds the cost without it).

### Known limitation
- None of the Chrome-side changes in this release could be verified against
  the live drive.google.com DOM — interactive browser automation
  (Computer Use write access, Claude-in-Chrome) was unavailable this
  session. Selectors are layered/defensive and reasoned from documented
  Google Drive DOM conventions, but are unverified. See RELEASE_NOTES.md
  for what was and wasn't checked, including a concrete, observed risk
  (the account seen mid-session had Drive set to Thai, which may affect
  text-based matching).

## [5.2.0] - Production readiness

### Fixed
- Cancelling or pausing a large file mid-download while it was using the
  multi-threaded ranged path silently ignored the cancellation and started
  a brand-new single-stream download instead of stopping — the error
  handling didn't distinguish "the user stopped this" from "one part had a
  transient failure," since both surface the same error type. Now checks
  actual task-cancellation state instead of inferring it from the error.
- Menu Bar Mode's popover rendered far narrower than designed, breaking
  the action-button row layout (buttons wrapped instead of sitting side by
  side). `MenuBarExtra` needs `.menuBarExtraStyle(.window)` for custom
  SwiftUI layouts — without it, rich content gets squeezed into a
  traditional-menu sizing model it wasn't designed for.
- "Open Window" in the menu bar could spawn a duplicate main window
  instead of focusing the existing one. The actual cause wasn't the
  button's own logic (which was already correctly guarding against it) —
  activating the app was triggering AppKit's default window-reopen
  handling independently. Fixed with an `NSApplicationDelegate` that makes
  reopen a no-op whenever a window already exists.
- Menu Bar Mode showed the raw Drive URL instead of the file/folder name
  for the active download and queue rows (main window already showed the
  name; this was a menu-bar-only regression from the same v5.1 change).
- Added accessibility labels to several icon-only buttons in Menu Bar Mode
  (quit, preferences, reveal/retry/remove) that had a tooltip but no
  VoiceOver label.

### Verified (no code change)
- Zero leaks and stable idle CPU/memory across repeated menu bar
  open/close cycles.
- Debug and Release builds clean with zero app-code warnings; Safari
  extension project rebuilds clean (no Safari-specific changes this
  release, per scope — Chrome remains the only browser worked on).

## [5.1.0] - Chrome integration

### Added
- Menu Bar Mode: the menu bar extra now shows live queue/progress, with
  Pause/Resume/Cancel on the active download and per-item actions, sharing
  the same live state as the main window (previously each held its own
  independent, out-of-sync copy)
- Download-complete notifications gained an "Open DropDrive" action
  alongside "Reveal in Finder"

### Fixed
- Chrome extension: the injected "Send to DropDrive" button never worked —
  `content.js` referenced a `class` before its declaration, which throws
  and aborts the whole script in JavaScript (no hoisting for classes the
  way there is for functions)
- Chrome extension: the "Send to DropDrive" context menu could appear on
  any website, not just Google Drive, because the page-context menu item
  only had `targetUrlPatterns` (which constrains link/image targets) and
  no `documentUrlPatterns` (which constrains the page itself)
- Chrome extension: removed an unused `scripting` permission and a
  manifest `icons` block pointing at image files that don't exist (both
  would surface as load-time warnings/errors in `chrome://extensions`)
- Removed a second, unwired deep-link handler and environment key in
  `DropDriveApp.swift` that duplicated (and could have silently diverged
  from) the one actually in use
- Removed a forked, drifted copy of the browser-extension JS that had
  been placed inside the Safari extension's app folder; the Xcode project
  was never pointed at it, so it was dead weight, and Safari continues to
  reference the single Chrome source of truth directly

### Changed
- The `dropdrive://` deep link host is now consistently `download`
  (`dropdrive://download?url=...`) everywhere it's emitted — Chrome
  extension, Safari extension, Share Extension. The app-side handler was
  already host-agnostic, so this is a producer-side consistency fix, not
  a breaking change.
- Chrome/Safari extension messaging simplified: the content script asks
  the background service worker to open DropDrive (`chrome.tabs.update`
  isn't available to a content script); nothing else builds or sends the
  deep link independently anymore.

## [4.0.0] - Productivity sprint

### Added
- Resumable downloads (app quit, network drop, or explicit pause), with
  graceful fallback to a fresh restart when resume isn't possible
- Optional bandwidth limit (Unlimited / 5 / 10 / 20 MB/s / Custom)
- Multi-threaded ranged downloads for large files when the server supports it
- Smart destination naming — collisions get `(1)`, `(2)`, … instead of being
  overwritten
- Pause/Resume for the whole download queue
- Drag-and-drop reordering of pending queue items
- Duplicate-download detection now also checks Recent Downloads across past
  sessions, not just the current one
- Search Recent Downloads by name
- Lightweight local download statistics (total downloads/files/size) in
  Preferences — no analytics, no telemetry
- Chrome extension, Safari extension, and a native Share Extension, all
  sending links into DropDrive via a new `dropdrive://` URL scheme
- `.fileURL` (e.g. dragged `.webloc` files) added to drag-and-drop support,
  alongside the existing URL/plain-text handling

### Fixed
- Google Drive "shortcut" items (added via *Add shortcut to Drive*) failed
  to download; they're now resolved to their real target transparently
- Links carrying a Drive `resourcekey` parameter previously 404'd; the key
  is now parsed and sent with every request for that item

### Changed
- The download-complete notification's action is now labeled "Reveal in
  Finder" (previously "Open Folder"); behavior was already reveal-in-Finder

## [2.1.1] - Final release sprint

### Fixed
- Drag-and-drop now correctly falls back to a dropped item's plain-text
  representation when its URL representation doesn't parse as a Drive
  link, instead of giving up (a provider can offer both, and the URL one
  isn't always the useful one)

### Added
- PRIVACY.md — a concrete description of what DropDrive does and doesn't
  do with your data
- RELEASE_NOTES.md for this release

### Verified
- Full project audit: no dead code, no duplicate logic, no unused assets,
  no TODO/FIXME/HACK markers, zero warnings in Debug and Release
- All documented user flows reviewed against source: public/private
  file/folder downloads, invalid/deleted links, OAuth, cancel/retry,
  progress, Recent Downloads, drag-and-drop, Preferences, menu bar, About
  panel, accessibility, keyboard navigation, Dark/Light Mode

## [2.1.0] - Production polish sprint

### Added
- "Reveal in Finder" and "Copy Google Drive Link" on every Recent Downloads entry (right-click)
- "Clear History" for Recent Downloads
- Recent download history now persists across launches
- Drag-and-drop of Google Drive links onto the main window
- Preferences window: default download folder, open Finder on completion, notification sound, launch at login
- Native menu bar item (Open DropDrive, Recent Downloads, Preferences, Quit)
- Optional GitHub Releases update checker (notify-only; never auto-downloads or auto-installs)
- Production repo assets: README, CHANGELOG, LICENSE, CONTRIBUTING, issue/PR templates

### Fixed
- Single-file download completion message no longer reads as "saved to" the file itself
- About panel no longer shows the build number twice
- About panel version string is now read from the bundle instead of being hardcoded

### Changed
- Recent download history moved from in-memory view state into a persisted, shared store

## [2.0.1]

### Fixed
- Removed dead code: unused `GoogleSignInSwift` package dependency, unused `DropDriveViewModel` state, unused `DownloadRequest` field
- Card and input field backgrounds now render correctly in both Light and Dark Mode (previously assumed Dark Mode only)
- Recent Downloads status icons now have VoiceOver labels

## [2.0.0-Dev] - Smart Link Analysis

### Added
- Smart Link Analysis: paste-to-preview before downloading, with public/private detection and file/folder support
- Destination folder memory and window frame persistence across launches
- Native completion notifications
- Sanitized, user-friendly error messages
- Invalid-link detection with inline feedback
- Paste/Clear affordances, Return-to-confirm, Escape-to-cancel

## [1.0.0-beta] - Initial release

### Added
- Google Sign-In and Drive API access (including Shared Drives)
- Folder and file downloads, with Google Docs/Sheets/Slides export support
- Real-time progress (bytes, speed, ETA) with cancel support
- Native macOS UI with light/dark appearance support

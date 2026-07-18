# DropDrive v6.4.0 Release Notes

Two hands-free ways to feed the queue: from your iPhone, and from any
right-click.

## Send from phone (new in 6.4.0)

Share a link on your iPhone → a small Shortcut saves it into the
DropDrive folder in iCloud Drive → the Mac picks it up within seconds,
queues it (TikTok/YouTube/IG/Drive alike), notifies you, and starts
downloading. Setup instructions ship with this release; the toggle
lives in Preferences.

## Right-click → Download with DropDrive (new in 6.4.0)

Select link text anywhere on the Mac — LINE, Notes, a web page — and
right-click → Services → Download with DropDrive. No copying, no window.

## From 6.3.0

The video card got eyes and scissors: real thumbnails, and trim-before-
download.

## Thumbnail preview (new in 6.3.0)

The confirm card for a video link now shows the actual thumbnail with a
duration badge — confirm the right clip before a single byte downloads.

## Trim to a section (new in 6.3.0)

Tick "ตัดเฉพาะช่วง" on the card, enter start and end times (0:10 –
1:30; hours work too), and DropDrive downloads only that section, cut
at keyframes, saved with a "(clip)" suffix. Combine it with MP3 to pull
just the chorus out of a long video.

## Instagram (new in 6.2.0)

Public Instagram posts and reels download like any other video link —
paste, confirm, video or MP3. Private or login-walled content fails
with the site's actual error instead of pretending to work.

## Download as MP3 (new in 6.1.0)

The confirm card for a TikTok / YouTube / Facebook link has a Video /
MP3 switch. Pick MP3 and DropDrive extracts the audio through its
bundled ffmpeg at best VBR quality — a "Converting to MP3…" stage shows
in the progress card, the queue row carries a music-note icon, and the
.mp3 lands in your chosen folder like any other download.

## Video downloads (from 6.0.0)

DropDrive learned a second trick: paste a TikTok, YouTube, or Facebook
link and it downloads the video — no "no watermark" websites, no ads.

## Video downloads

The same paste box now recognizes video links. Paste one and the
analysis card shows the title, uploader, and approximate size; confirm
and it downloads into your chosen folder with live progress, exactly
like a Drive download. TikTok videos come out watermark-free (the same
source those converter sites serve). YouTube downloads best video +
audio merged at full quality. Queue, pause/resume, cancel-with-cleanup,
auto-retry UI, history, and notifications all apply.

Under the hood this bundles universal builds of yt-dlp and ffmpeg, which
is why the app got noticeably bigger this release. Fair warning: bulk
downloading from these platforms is against their terms of service —
this is a personal tool, use it for your own stuff.

## Upgrading

Quit the old version (menu bar icon → power button), open the DMG, drag
DropDrive.app to Applications, Replace. First launch may need
right-click → Open once.

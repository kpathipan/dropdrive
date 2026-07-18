# DropDrive v6.1.0 Release Notes

Video links can now come down as MP3, on top of v6.0.0's video
downloads.

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

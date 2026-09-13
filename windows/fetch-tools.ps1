$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$tools = Join-Path $root "DropDrive.Windows/Tools"
New-Item -ItemType Directory -Force $tools | Out-Null

Invoke-WebRequest "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -OutFile (Join-Path $tools "yt-dlp.exe")
$archive = Join-Path $env:TEMP "ffmpeg-master-latest-win64-gpl-shared.zip"
Invoke-WebRequest "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl-shared.zip" -OutFile $archive
$expanded = Join-Path $env:TEMP "dropdrive-ffmpeg"
Remove-Item $expanded -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive $archive $expanded
$bin = Get-ChildItem $expanded -Filter ffmpeg.exe -Recurse | Select-Object -First 1 | Select-Object -ExpandProperty Directory
if (!$bin) { throw "ffmpeg.exe was not found in the downloaded archive." }
Copy-Item (Join-Path $bin.FullName "ffmpeg.exe"), (Join-Path $bin.FullName "ffprobe.exe"), `
  (Join-Path $bin.FullName "*.dll") $tools

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$tools = Join-Path $root "DropDrive.Windows/Tools"
New-Item -ItemType Directory -Force $tools | Out-Null

$engine = Get-Content (Join-Path $root '../packaging/media-engine.json') -Raw | ConvertFrom-Json
Invoke-WebRequest "https://github.com/yt-dlp/yt-dlp/releases/download/$($engine.ytDlpVersion)/yt-dlp.exe" -OutFile (Join-Path $tools "yt-dlp.exe")
if ((Get-FileHash (Join-Path $tools 'yt-dlp.exe') -Algorithm SHA256).Hash.ToLowerInvariant() -ne $engine.windowsSha256) { throw 'yt-dlp checksum mismatch' }
# Small standalone JS runtime required for YouTube's challenge solver. Pin and
# verify it rather than depending on Node/Deno installed on the user's PC.
$quickJs = Join-Path $tools "qjs.exe"
Invoke-WebRequest "https://github.com/quickjs-ng/quickjs/releases/download/v0.16.2/qjs-windows-x86_64.exe" -OutFile $quickJs
if ((Get-FileHash $quickJs -Algorithm SHA256).Hash -ne "7B27412DE844403545BD151FBE49191B4D5B91A9E15B5DB7C863FEA54639A82B") {
  throw "QuickJS checksum mismatch."
}
Invoke-WebRequest "https://raw.githubusercontent.com/quickjs-ng/quickjs/v0.16.2/LICENSE" -OutFile (Join-Path $tools "LICENSE-quickjs.txt")
& $quickJs -e "console.log('DropDrive JavaScript runtime ready')"
if ($LASTEXITCODE -ne 0) { throw "QuickJS runtime did not start." }
$archive = Join-Path $env:TEMP "ffmpeg-master-latest-win64-gpl-shared.zip"
Invoke-WebRequest "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl-shared.zip" -OutFile $archive
$expanded = Join-Path $env:TEMP "dropdrive-ffmpeg"
Remove-Item $expanded -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive $archive $expanded
$bin = Get-ChildItem $expanded -Filter ffmpeg.exe -Recurse | Select-Object -First 1 | Select-Object -ExpandProperty Directory
if (!$bin) { throw "ffmpeg.exe was not found in the downloaded archive." }
Copy-Item (Join-Path $bin.FullName "ffmpeg.exe"), (Join-Path $bin.FullName "ffprobe.exe"), `
  (Join-Path $bin.FullName "*.dll") $tools

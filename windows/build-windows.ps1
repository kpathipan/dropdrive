param([string]$Version = "6.25.1")
$ErrorActionPreference = "Stop"
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "A stable X.Y.Z version is required." }
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$project = Join-Path $root "DropDrive.Windows/DropDrive.Windows.csproj"
$publish = Join-Path $root "artifacts/publish"
$releases = Join-Path $root "artifacts/releases"

Remove-Item $publish, $releases -Recurse -Force -ErrorAction SilentlyContinue
dotnet publish $project -c Release -r win-x64 --self-contained true -p:Version=$Version -o $publish
if ($LASTEXITCODE -ne 0) { throw "Windows publish failed." }
if (!(Test-Path (Join-Path $publish "Tools/yt-dlp.exe"))) {
  throw "Tools/yt-dlp.exe is missing. Run fetch-tools.ps1 first."
}
if (!(Test-Path (Join-Path $publish "Tools/qjs.exe"))) {
  throw "Tools/qjs.exe is missing. YouTube needs the bundled JavaScript runtime."
}

dotnet tool restore --tool-manifest (Join-Path $root ".config/dotnet-tools.json")
if ($LASTEXITCODE -ne 0) { throw "Velopack restore failed." }
Push-Location $root
try {
  dotnet tool run vpk pack --runtime win-x64 --packId com.dropdrive.windows --packVersion $Version `
    --packDir $publish --mainExe DropDrive.exe --packTitle DropDrive `
    --icon (Join-Path $root "DropDrive.Windows/Assets/dropdrive.ico") --outputDir $releases
  if ($LASTEXITCODE -ne 0) { throw "Windows packaging failed." }
} finally { Pop-Location }

Write-Host "Installer: $releases/com.dropdrive.windows-win-Setup.exe"

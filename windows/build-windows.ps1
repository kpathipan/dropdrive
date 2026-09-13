param([string]$Version = "0.5.0")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$project = Join-Path $root "DropDrive.Windows/DropDrive.Windows.csproj"
$publish = Join-Path $root "artifacts/publish"
$releases = Join-Path $root "artifacts/releases"

Remove-Item $publish, $releases -Recurse -Force -ErrorAction SilentlyContinue
dotnet publish $project -c Release -r win-x64 --self-contained true -p:Version=$Version -o $publish
if (!(Test-Path (Join-Path $publish "Tools/yt-dlp.exe"))) {
  throw "Tools/yt-dlp.exe is missing. Run fetch-tools.ps1 first."
}

dotnet tool restore --tool-manifest (Join-Path $root ".config/dotnet-tools.json")
Push-Location $root
try {
  dotnet tool run vpk pack --runtime win-x64 --packId com.dropdrive.windows --packVersion $Version `
    --packDir $publish --mainExe DropDrive.exe --packTitle DropDrive `
    --icon (Join-Path $root "DropDrive.Windows/Assets/dropdrive.ico") --outputDir $releases
} finally { Pop-Location }

Write-Host "Installer: $releases/com.dropdrive.windows-win-Setup.exe"

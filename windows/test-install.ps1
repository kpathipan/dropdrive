# Destructive installation tests belong only on the disposable Windows runner.
$ErrorActionPreference = "Stop"
if ($env:GITHUB_ACTIONS -ne "true") { throw "Run installer integration tests on the disposable CI runner only." }
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Join-Path $env:LOCALAPPDATA "com.dropdrive.windows"
$stateRoot = Join-Path $env:LOCALAPPDATA "DropDrive"
$oldSetup = Join-Path $env:RUNNER_TEMP "dropdrive-previous-0.5.1.exe"
Invoke-WebRequest "https://github.com/kpathipan/dropdrive/releases/download/windows-v0.5.1/com.dropdrive.windows-win-Setup.exe" -OutFile $oldSetup

function Install-DropDrive([string]$setup) {
    $process = Start-Process $setup -ArgumentList "--silent" -PassThru
    if (!$process.WaitForExit(60000)) { $process.Kill($true); throw "Installer timed out." }
    if ($process.ExitCode -ne 0) { throw "Installer failed with exit code $($process.ExitCode)." }
}

Install-DropDrive $oldSetup
$exe = Join-Path $appRoot "current/DropDrive.exe"
if (!(Test-Path $exe)) { throw "Previous release did not install to its expected stable path." }
New-Item -ItemType Directory -Force $stateRoot | Out-Null
$settingsPath = Join-Path $stateRoot "settings.json"
$queuePath = Join-Path $stateRoot "queue.json"
$sentinelDestination = Join-Path $env:RUNNER_TEMP "DropDrive retained destination"
New-Item -ItemType Directory -Force $sentinelDestination | Out-Null
@{ Destination = $sentinelDestination; CheckUpdatesAutomatically = $false; HideToTray = $false } |
    ConvertTo-Json | Set-Content $settingsPath -Encoding utf8
$retainedId = [guid]::NewGuid().ToString()
ConvertTo-Json -Depth 5 -InputObject @(@{ Id = $retainedId; Url = "https://example.com/retained.mp4"; Name = "Retained queue";
    Status = "Paused"; Destination = $sentinelDestination }) | Set-Content $queuePath -Encoding utf8

Install-DropDrive (Join-Path $root "artifacts/releases/com.dropdrive.windows-win-Setup.exe")
if (!(Test-Path $exe)) { throw "Upgrade removed the stable executable path." }
$version = (Get-Item $exe).VersionInfo.ProductVersion
if (!$version.StartsWith($env:DROPDRIVE_WINDOWS_VERSION)) { throw "Installed version is $version, not the new build." }
$settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
$queue = @(Get-Content $queuePath -Raw | ConvertFrom-Json)
if ($settings.Destination -ne $sentinelDestination -or $queue[0].Id -ne $retainedId) { throw "Upgrade lost persisted state." }

$process = Start-Process $exe -PassThru
try {
    Start-Sleep -Seconds 5
    $process.Refresh()
    if ($process.HasExited -or $process.MainWindowTitle -ne "DropDrive") { throw "Installed upgraded app did not open." }
    if (!(Test-Path (Join-Path $appRoot "Update.exe"))) { throw "Installed updater is missing." }
    Write-Host "PASS installed upgrade: 0.5.1 -> $version; settings and paused queue retained; installed app opens."
} finally {
    if (!$process.HasExited) { Stop-Process -Id $process.Id -Force }
}

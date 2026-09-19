param([string]$ExpectedVersion = "0.7.0")
$ErrorActionPreference = "Stop"
if ($env:GITHUB_ACTIONS -ne "true") { throw "Automatic update tests are restricted to disposable Windows CI." }
$setup = Join-Path $env:RUNNER_TEMP "DropDrive-update-source-0.6.0.exe"
Invoke-WebRequest "https://github.com/kpathipan/dropdrive/releases/download/windows-v0.6.0/com.dropdrive.windows-win-Setup.exe" -OutFile $setup
$installer = Start-Process $setup -ArgumentList "--silent" -PassThru
if (!$installer.WaitForExit(60000) -or $installer.ExitCode -ne 0) { throw "Source installation failed." }
$state = Join-Path $env:LOCALAPPDATA "DropDrive"
New-Item -ItemType Directory -Force $state | Out-Null
$destination = Join-Path $env:RUNNER_TEMP "Retained-auto-update-destination"
New-Item -ItemType Directory -Force $destination | Out-Null
@{ Destination = $destination; CheckUpdatesAutomatically = $true; HideToTray = $false;
   LastAutomaticUpdateCheckUtc = [DateTimeOffset]::UtcNow.AddDays(-2).ToString("o") } | ConvertTo-Json | Set-Content (Join-Path $state "settings.json") -Encoding utf8
$id = [guid]::NewGuid().ToString()
ConvertTo-Json -Depth 5 -InputObject @(@{ Id = $id; Url = "https://example.com/keep.mp4"; Name = "Retained"; Status = "Paused"; Destination = $destination }) | Set-Content (Join-Path $state "queue.json") -Encoding utf8
$exe = Join-Path $env:LOCALAPPDATA "com.dropdrive.windows/current/DropDrive.exe"
$process = Start-Process $exe -PassThru
try {
  $deadline = [DateTime]::UtcNow.AddMinutes(4)
  do {
    Start-Sleep -Seconds 5
    $version = (Get-Item $exe).VersionInfo.ProductVersion
    $running = @(Get-Process DropDrive -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe -and $_.MainWindowTitle -eq "DropDrive" })
  } while ((!$version.StartsWith($ExpectedVersion) -or $running.Count -ne 1) -and [DateTime]::UtcNow -lt $deadline)
  if (!$version.StartsWith($ExpectedVersion) -or $running.Count -ne 1) { throw "Remote update/restart failed: version=$version, running=$($running.Count)" }
  $settings = Get-Content (Join-Path $state "settings.json") -Raw | ConvertFrom-Json
  $queue = @(Get-Content (Join-Path $state "queue.json") -Raw | ConvertFrom-Json)
  if ($settings.Destination -ne $destination -or $queue[0].Id -ne $id) { throw "Remote update lost settings/queue." }
  Write-Host "PASS real public feed auto-update: 0.6.0 -> $version, one process, state retained, app restarted."
} finally {
  Get-Process DropDrive -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe } | Stop-Process -Force
}

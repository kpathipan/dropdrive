# DropDrive for Windows

Windows-first desktop client with a normal resizable window, background tray
presence, direct/media downloads and automatic in-place updates.

## Local Windows build

Requires Windows 10/11 and the .NET 10 SDK.

```powershell
./fetch-tools.ps1
./build-windows.ps1 -Version 0.2.0
```

The installer is written to `artifacts/releases/com.dropdrive.windows-win-Setup.exe`.
Installed builds check the public GitHub release feed on launch. Development
builds intentionally skip update installation.

## Release

Push a `windows-v<semver>` tag only after testing the installer on Windows. The
Windows workflow builds the EXE, creates the Velopack feed and publishes that
feed to a GitHub Release. Signing variables can be added to the workflow once an
Authenticode certificate is available.

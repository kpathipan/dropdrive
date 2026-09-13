# ADR-0001: Windows desktop client and updates

**Status:** Accepted
**Date:** 2026-09-13

## Context

DropDrive for macOS is a SwiftUI menu-bar application. Its UI, Keychain access,
Quick Look integration and updater are macOS-specific. The Windows edition needs
a normal desktop window, system-tray behavior, a standalone installer and safe
in-place updates without changing the Mac application.

## Decision

Build a separate Windows client under `windows/` with .NET 10 and Avalonia 12.
Package releases with Velopack, use its GitHub release source for automatic
delta-capable updates, and produce a `com.dropdrive.windows-win-Setup.exe`
installer. Windows
release tags use `windows-v<semver>` so they cannot be confused with Mac releases.

## Consequences

- Mac and Windows UI can evolve independently.
- Windows releases must be built and smoke-tested on Windows.
- Public distribution requires an Authenticode certificate; unsigned local
  builds may trigger Microsoft Defender SmartScreen.

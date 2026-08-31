# Contributing to DropDrive

Thanks for your interest in improving DropDrive.

## Before you start

Before starting a substantial change, open a
[GitHub issue](https://github.com/kpathipan/dropdrive/issues) to discuss it.
This avoids spending time on a pull request that does not fit the project's
direction.

## Development setup

1. Open `DropDrive.xcodeproj` in Xcode.
2. Set your own Development Team under Signing & Capabilities.
3. Fill in `DropDrive/Info.plist` with your own `GIDClientID` /
   `REVERSED_CLIENT_ID` (from a Google Cloud OAuth client) so Sign-In works
   locally. `GoogleAPIKey` is optional.

## Guidelines

- Match the existing MVVM structure: `Models/`, `Services/`, `ViewModels/`,
  `Views/`. Keep views presentation-only; put logic in services/view models.
- Don't add third-party dependencies without discussing them first — the
  project intentionally keeps its dependency footprint small (Google Sign-In
  only).
- Run both Debug and Release builds before opening a PR and confirm there are
  no new warnings.
- Keep commits focused; explain the "why" in the commit message, not just
  the "what".

## Reporting bugs

Use the bug report issue template and include:
- macOS version
- DropDrive version (see About DropDrive)
- Steps to reproduce
- What you expected vs. what happened

## Security

If you find a security issue (for example, involving credentials or sandboxed
file access), do not open a public issue. Report it through a
[private GitHub security advisory](https://github.com/kpathipan/dropdrive/security/advisories/new).

## Privacy

Changes that add network calls, new local storage, or new data collection
should be reflected in [PRIVACY.md](PRIVACY.md) as part of the same PR.

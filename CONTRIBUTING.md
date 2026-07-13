# Contributing to DropDrive

Thanks for your interest in improving DropDrive.

## Before you start

This project doesn't have a public issue tracker or contribution workflow set
up yet. If you'd like to contribute, please open an issue first to discuss
what you'd like to change — this avoids wasted effort on pull requests that
might not fit the project's direction.

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

If you find a security issue (e.g. related to credential handling or the
sandboxed file access), please do not open a public issue — see
[SECURITY policy / contact information to be added].

# DropDrive v5.0.0 Release Notes

**Release Date:** July 14, 2026

## Overview

DropDrive v5.0.0 represents a major update introducing seamless browser integration, enhanced notification system, and improved user experience with the new Menu Bar Mode.

## New Features

### 🌐 Browser Integration
- **IDM-Style Download Workflow**: Direct integration with Safari browser
- Download button injected into Google Drive interface
- One-click download without copy-paste
- Context menu support for right-click downloads
- Automatic launch of DropDrive app when download initiated

### 🔗 Deep Link Protocol
- `dropdrive://download?url=<share-link>` support
- Seamless communication between browser extension and desktop app
- Native URL scheme handling
- Automatic app activation and window management

### 📊 Enhanced Menu Bar Mode
- **Queue Management**: View all active downloads at a glance
- **Progress Tracking**: Real-time download progress with speed estimation
- **Pause/Resume**: Temporarily pause downloads and resume later
- **Reveal in Finder**: Quick access to downloaded files
- **Status Indicator**: Color-coded status for each download item
- **Minimize Window Workflow**: Run DropDrive entirely from menu bar

### 🔔 Notification 2.0
- **Smart Notifications**: Get alerted when downloads complete
- **Actionable Alerts**: Two-button notifications
  - "Reveal in Finder" - Opens the downloaded file location
  - "Open DropDrive" - Brings app to foreground
- **Sound Support**: Optional audio notification

## Improvements

- Optimized memory usage for large download queues
- Improved visual feedback during file downloads
- Better error handling and recovery
- Smoother pause/resume transitions
- Enhanced Safari extension compatibility

## Technical Details

### Build Information
- **Build Date**: July 14, 2026
- **Version**: 5.0.0
- **Build Number**: 8
- **Minimum macOS**: macOS 11.0+
- **Architectures**: Intel & Apple Silicon (Universal Binary)

### Known Limitations
- Hardened Runtime requires rebuild (currently in Release Candidate phase)
- DMG distribution pending final code signing configuration
- Safari extension requires user permissions grant

## Installation

1. Download DropDrive v5.0.0
2. Install to Applications folder
3. Enable Safari extension in Settings → Extensions
4. Grant necessary permissions for Finder access
5. Grant notification permissions when prompted

## Migration Notes

- Previous queue data is preserved
- Settings are carried over from v4.x
- No action required for existing users

## Bug Fixes

- Fixed notification delegate crashes
- Corrected queue item status transitions
- Improved pause/resume state management
- Fixed menu bar display issues

## Support

For issues or feature requests:
- GitHub: https://github.com/yourorg/dropdrive
- Email: support@dropdrive.app

---

**Thank you for using DropDrive!**

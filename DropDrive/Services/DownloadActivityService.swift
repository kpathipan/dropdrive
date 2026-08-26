import Foundation

/// Keeps an active transfer from being interrupted by idle system sleep. Each
/// token belongs to one network attempt and is ended before an automatic-retry
/// delay, so a disconnected Mac is still free to sleep while DropDrive waits.
nonisolated enum DownloadActivityService {
    static func begin() -> NSObjectProtocol {
        ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "DropDrive is downloading a file"
        )
    }

    static func end(_ token: NSObjectProtocol) {
        ProcessInfo.processInfo.endActivity(token)
    }
}

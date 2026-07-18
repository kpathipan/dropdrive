import AppKit
import UserNotifications

enum NotificationService {
    static let openFolderActionID = "OPEN_FOLDER"
    static let openDropDriveActionID = "OPEN_DROPDRIVE"
    static let downloadCategoryID = "DOWNLOAD_COMPLETE"
    static let folderPathKey = "folderPath"

    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let revealAction = UNNotificationAction(identifier: openFolderActionID, title: "Reveal in Finder", options: [])
        let openDropDriveAction = UNNotificationAction(identifier: openDropDriveActionID, title: "Open DropDrive", options: [])
        let downloadCategory = UNNotificationCategory(
            identifier: downloadCategoryID,
            actions: [revealAction, openDropDriveAction],
            intentIdentifiers: [],
            options: []
        )

        let updateCategory = UNNotificationCategory(
            identifier: UpdateChecker.updateAvailableCategoryID,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([downloadCategory, updateCategory])
    }

    /// Generic one-off notification (phone-inbox arrivals, service handoffs).
    static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func notifyDownloadComplete(name: String, folderURL: URL, playSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = name
        content.categoryIdentifier = downloadCategoryID
        content.userInfo = [folderPathKey: folderURL.path]
        if playSound {
            content.sound = .default
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    private override init() {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        let actionID = response.actionIdentifier

        // Handle download complete notification
        if content.categoryIdentifier == NotificationService.downloadCategoryID {
            if actionID == NotificationService.openFolderActionID || actionID == UNNotificationDefaultActionIdentifier {
                // Reveal in Finder
                if let path = content.userInfo[NotificationService.folderPathKey] as? String {
                    await MainActor.run {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                }
            } else if actionID == NotificationService.openDropDriveActionID {
                // Menu-bar-only app: there is no window to order front, and the
                // menu bar extra can't be popped open programmatically — just
                // activate so the menu bar icon is where the user left it.
                await MainActor.run {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            return
        }

        // Handle update available notification
        if actionID == UNNotificationDefaultActionIdentifier,
           content.categoryIdentifier == UpdateChecker.updateAvailableCategoryID,
                  let urlString = content.userInfo[UpdateChecker.releaseURLKey] as? String,
                  let url = URL(string: urlString) {
            await MainActor.run {
                _ = NSWorkspace.shared.open(url)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

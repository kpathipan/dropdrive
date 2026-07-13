import AppKit
import UserNotifications

enum NotificationService {
    static let openFolderActionID = "OPEN_FOLDER"
    static let downloadCategoryID = "DOWNLOAD_COMPLETE"
    static let folderPathKey = "folderPath"

    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let openAction = UNNotificationAction(identifier: openFolderActionID, title: "Open Folder", options: [])
        let category = UNNotificationCategory(
            identifier: downloadCategoryID,
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    static func notifyDownloadComplete(name: String, folderURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = name
        content.categoryIdentifier = downloadCategoryID
        content.userInfo = [folderPathKey: folderURL.path]

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
        guard response.actionIdentifier == NotificationService.openFolderActionID
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            let path = response.notification.request.content.userInfo[NotificationService.folderPathKey] as? String else {
            return
        }

        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

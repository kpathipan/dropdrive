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
        let downloadCategory = UNNotificationCategory(
            identifier: downloadCategoryID,
            actions: [openAction],
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
        let acted = response.actionIdentifier == NotificationService.openFolderActionID
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        guard acted else { return }

        if content.categoryIdentifier == NotificationService.downloadCategoryID,
           let path = content.userInfo[NotificationService.folderPathKey] as? String {
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        } else if content.categoryIdentifier == UpdateChecker.updateAvailableCategoryID,
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

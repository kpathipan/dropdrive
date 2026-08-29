import AppKit
import UserNotifications

enum NotificationService {
    static let openFolderActionID = "OPEN_FOLDER"
    static let openDropDriveActionID = "OPEN_DROPDRIVE"
    static let downloadCategoryID = "DOWNLOAD_COMPLETE"
    static let attentionCategoryID = "DOWNLOAD_ATTENTION"
    static let openAttentionActionID = "OPEN_ATTENTION"
    static let folderPathKey = "folderPath"

    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let revealAction = UNNotificationAction(
            identifier: openFolderActionID,
            title: tr("Reveal in Finder", "เปิดใน Finder"),
            options: []
        )
        let openDropDriveAction = UNNotificationAction(
            identifier: openDropDriveActionID,
            title: tr("Open DropDrive", "เปิด DropDrive"),
            options: []
        )
        let downloadCategory = UNNotificationCategory(
            identifier: downloadCategoryID,
            actions: [revealAction, openDropDriveAction],
            intentIdentifiers: [],
            options: []
        )

        let updateCategory = UNNotificationCategory(
            identifier: UpdateService.updateAvailableCategoryID,
            actions: [UNNotificationAction(
                identifier: UpdateService.installActionID,
                title: tr("Update now", "อัปเดตเลย"),
                options: [.foreground]
            )],
            intentIdentifiers: [],
            options: []
        )

        let attentionCategory = UNNotificationCategory(
            identifier: attentionCategoryID,
            actions: [UNNotificationAction(
                identifier: openAttentionActionID,
                title: tr("Review in DropDrive", "เปิดดูใน DropDrive"),
                options: [.foreground]
            )],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([downloadCategory, updateCategory, attentionCategory])
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
        content.title = tr("Download Complete", "ดาวน์โหลดเสร็จแล้ว")
        content.body = name
        content.categoryIdentifier = downloadCategoryID
        content.userInfo = [folderPathKey: folderURL.path]
        if playSound {
            content.sound = .default
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// One notification per affected queue row. Reusing the identifier replaces
    /// a pending notification instead of creating one for every retry attempt.
    static func notifyAttention(itemID: UUID, name: String, kind: QueueItem.AttentionKind) {
        guard kind == .network || kind == .destination else { return }
        let identifier = attentionIdentifier(itemID)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = kind == .destination
            ? tr("Destination drive disconnected", "ไดรฟ์ปลายทางถูกถอด")
            : tr("Download connection lost", "การดาวน์โหลดขาดการเชื่อมต่อ")
        content.body = name
        content.categoryIdentifier = attentionCategoryID
        content.userInfo = ["queueItemID": itemID.uuidString]

        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    static func clearAttention(itemID: UUID) {
        let identifiers = [attentionIdentifier(itemID)]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private static func attentionIdentifier(_ itemID: UUID) -> String {
        "dropdrive.attention.\(itemID.uuidString)"
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
                await MainActor.run {
                    StatusItemController.current?.showPopover()
                }
            }
            return
        }

        if content.categoryIdentifier == NotificationService.attentionCategoryID {
            if actionID == NotificationService.openAttentionActionID
                || actionID == UNNotificationDefaultActionIdentifier {
                await MainActor.run {
                    StatusItemController.current?.showAttention()
                }
            }
            return
        }

        // Handle update available notification
        guard content.categoryIdentifier == UpdateService.updateAvailableCategoryID else { return }
        // Either button installs — the notification's whole purpose is to save
        // the user a trip into the app, so tapping the body shouldn't just open
        // a download page they then have to install by hand.
        if actionID == UpdateService.installActionID || actionID == UNNotificationDefaultActionIdentifier {
            await MainActor.run {
                NSApp.activate(ignoringOtherApps: true)
                UpdateService.shared.installFromNotification()
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

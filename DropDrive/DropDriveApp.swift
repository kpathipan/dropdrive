import SwiftUI
import UserNotifications

/// Routes incoming URLs (Google sign-in callbacks and `dropdrive://` deep links
/// from the Share extension) to the shared view model, owns the menu bar status
/// item, and reopens that same popover when the app is launched again.
final class DropDriveAppDelegate: NSObject, NSApplicationDelegate {
    private let servicesProvider = ServicesProvider()
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
        // Right-click "Download with DropDrive" on selected text anywhere —
        // a plain NSServices entry + provider, no app extension involved.
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()
        // Start watching the iCloud Drive phone inbox.
        _ = PhoneInboxService.shared
        // Reclaim scratch space from downloads a previous run never finished.
        TempCleaner.sweepInBackground()
        // The menu bar presence (left-click opens the popover, right-click a
        // Quit menu). Driven manually via NSStatusItem rather than SwiftUI's
        // MenuBarExtra so right-click can show its own menu.
        statusController = StatusItemController()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            DropDriveViewModel.shared.handleIncomingURL(url)
        }
    }

    /// Fires when the user opens the app again from Finder/Launchpad while it's
    /// running. Keep the product's one-surface contract: reopening reveals the
    /// same menu-bar popover rather than inventing a separate app window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        StatusItemController.current?.showPopover()
        return false
    }
}

/// Receives the "Download with DropDrive" macOS Service: selected text from any
/// app arrives on the pasteboard, every link in it goes to the shared queue.
final class ServicesProvider: NSObject {
    @objc func downloadWithDropDrive(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        var text = pasteboard.string(forType: .string) ?? ""
        if text.isEmpty, let url = pasteboard.string(forType: .URL) {
            text = url
        }
        guard !text.isEmpty else { return }

        var links: [String] = []
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        detector?.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, _ in
            if let url = match?.url, url.scheme == "https" || url.scheme == "http" {
                links.append(url.absoluteString)
            }
        }
        guard !links.isEmpty else { return }

        Task { @MainActor in
            _ = await DropDriveViewModel.shared.receiveExternalLinks(
                links,
                sourceLabel: tr("from the Services menu", "จากเมนูคลิกขวา")
            )
        }
    }
}

extension Notification.Name {
    static let dropDriveShowSettings = Notification.Name("DropDrive.showSettings")
}

@main
struct DropDriveApp: App {
    @NSApplicationDelegateAdaptor(DropDriveAppDelegate.self) private var appDelegate

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationService.requestAuthorizationIfNeeded()
        UpdateService.shared.checkIfNeeded()
        UpdateService.shared.startPeriodicChecks()
    }

    var body: some Scene {
        // The UI is an NSStatusItem + NSPopover driven from the app delegate;
        // SwiftUI still needs one scene. Keyboard-first queue controls live in
        // the app command menu so they remain available while focus is inside a
        // text field or a review card.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button(tr("Settings…", "การตั้งค่า…")) {
                        StatusItemController.current?.showSettings()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
                CommandMenu("DropDrive") {
                    Button(tr("Choose destination…", "เลือกโฟลเดอร์ปลายทาง…")) {
                        DropDriveViewModel.shared.chooseDestinationFolder()
                    }
                    .keyboardShortcut("o", modifiers: .command)

                    Button(
                        DropDriveViewModel.shared.isQueuePaused
                            ? tr("Resume queue", "ทำต่อคิว")
                            : tr("Pause queue", "พักคิว")
                    ) {
                        if DropDriveViewModel.shared.isQueuePaused {
                            DropDriveViewModel.shared.resumeQueue()
                        } else {
                            DropDriveViewModel.shared.pauseQueue()
                        }
                    }
                    .keyboardShortcut(" ", modifiers: [])
                }
            }
    }
}

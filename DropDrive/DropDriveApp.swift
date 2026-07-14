import SwiftUI
import UserNotifications

/// Without this, activating the app (e.g. from the menu bar extra's "Open Window"
/// button) while a WindowGroup window is already open can still trigger AppKit's
/// default reopen handling and spawn a second window — this makes reopen a no-op
/// whenever a window already exists instead of leaving it to the default heuristic.
final class DropDriveAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if let existing = sender.windows.first(where: { $0.canBecomeMain }) {
            existing.makeKeyAndOrderFront(nil)
            return false
        }
        return true
    }
}

@main
struct DropDriveApp: App {
    // Set this once a public repository exists, e.g. URL(string: "https://github.com/yourorg/dropdrive")
    private static let githubURL: URL? = nil

    private static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(DropDriveAppDelegate.self) private var appDelegate

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationService.requestAuthorizationIfNeeded()
        UpdateChecker.shared.checkIfNeeded()
    }

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About DropDrive") {
                    showAboutPanel()
                }
            }
        }

        Settings {
            PreferencesView()
        }

        MenuBarExtra("DropDrive", systemImage: "tray.and.arrow.down.fill") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }

    private func showAboutPanel() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "5.2.0"

        let credits = NSMutableAttributedString(
            string: "Download Google Drive files and folders directly to your Mac.\n\nLicense: All Rights Reserved",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        )

        if let githubURL = Self.githubURL {
            credits.append(NSAttributedString(string: "\n"))
            let link = NSAttributedString(string: "GitHub", attributes: [.link: githubURL])
            credits.append(link)
        }

        NSApplication.shared.orderFrontStandardAboutPanel(
            options: [
                NSApplication.AboutPanelOptionKey.applicationName: "DropDrive",
                NSApplication.AboutPanelOptionKey.applicationVersion: "\(version) Development",
                NSApplication.AboutPanelOptionKey.credits: credits
            ]
        )
    }
}

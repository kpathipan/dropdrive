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

    /// SwiftUI's `WindowGroup` + `.onOpenURL` treats each incoming `dropdrive://`
    /// URL as a fresh scene-activation request, and on macOS this can spawn an
    /// entirely new window per link instead of routing to the one already open
    /// (the same class of bug `applicationShouldHandleReopen` above works around
    /// for the menu bar's "Open Window" button). Handling it here instead, once,
    /// directly against the shared view model, means an already-open window just
    /// updates in place — no `.onOpenURL` handler exists anywhere else in the app.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            DropDriveViewModel.shared.handleIncomingURL(url)
        }
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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "5.4.1"

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
                NSApplication.AboutPanelOptionKey.applicationVersion: "\(version) Beta",
                NSApplication.AboutPanelOptionKey.credits: credits
            ]
        )
    }
}

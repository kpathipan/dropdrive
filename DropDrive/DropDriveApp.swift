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
        // The window this creates apparently never becomes key/main (observed:
        // the didBecomeMainNotification-based sweep below never caught it), so
        // this is deliberately also swept explicitly, right where it's created,
        // rather than relying only on that notification firing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Self.closeDuplicateMainWindows()
        }
    }

    /// A separate, observed bug from the two above: `WindowGroup` can spawn more
    /// than one main-content window instance — on a plain cold launch with zero
    /// user interaction, and again later whenever a deep link arrives while the
    /// app is already running. Rather than chase the exact SwiftUI/AppKit
    /// scene-lifecycle cause, this enforces "exactly one main window" every time
    /// any window becomes main, not just once at launch.
    func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { _ in
            Self.closeDuplicateMainWindows()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Self.closeDuplicateMainWindows()
        }
    }

    /// `WindowAccessor` tags its window with `frameAutosaveName` from inside a
    /// `DispatchQueue.main.async` block (needed since `view.window` isn't set
    /// synchronously in `makeNSView`) — logged proof from a real repro showed that
    /// when multiple main windows appear together, that async tagging only wins
    /// the race for one of them, leaving the others with an empty autosave name.
    /// Filtering on that name alone was therefore missing most of the actual
    /// duplicates. `title == "DropDrive"` is set synchronously by SwiftUI for
    /// every `WindowGroup` window and was reliably present on all of them in that
    /// same log, so it's the one used here — Settings/Preferences windows get
    /// their own distinct system-provided title, not the app's display name.
    private static func closeDuplicateMainWindows() {
        let mainWindows = NSApplication.shared.windows.filter {
            $0.title == "DropDrive" && $0.canBecomeMain && $0.isVisible
        }
        guard mainWindows.count > 1 else { return }
        let keep = mainWindows.first(where: { $0.isKeyWindow }) ?? mainWindows.first
        for window in mainWindows where window !== keep {
            window.close()
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

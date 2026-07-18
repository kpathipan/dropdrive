import SwiftUI
import UserNotifications

/// Routes incoming URLs (Google sign-in callbacks and `dropdrive://` deep links
/// from the Share extension) to the shared view model. As a menu-bar-only app
/// there is no WindowGroup, so none of the old duplicate-window workarounds are
/// needed — the menu bar extra's window is the only UI.
final class DropDriveAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            DropDriveViewModel.shared.handleIncomingURL(url)
        }
    }
}

@main
struct DropDriveApp: App {
    @NSApplicationDelegateAdaptor(DropDriveAppDelegate.self) private var appDelegate

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationService.requestAuthorizationIfNeeded()
        UpdateChecker.shared.checkIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            MenuBarIconLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

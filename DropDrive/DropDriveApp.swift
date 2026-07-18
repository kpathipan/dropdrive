import SwiftUI
import UserNotifications

/// Routes incoming URLs (Google sign-in callbacks and `dropdrive://` deep links
/// from the Share extension) to the shared view model, and opens the fallback
/// window when the app is launched again while already running.
final class DropDriveAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            DropDriveViewModel.shared.handleIncomingURL(url)
        }
    }

    /// Fires when the user opens the app again from Finder/Launchpad while it's
    /// running. On a crowded menu bar (especially next to a notch) macOS can hide
    /// the status icon entirely, which would make a menu-bar-only app unreachable
    /// — this gives the same UI as a regular window instead.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        FallbackWindow.show()
        return false
    }
}

/// A plain window hosting the same view the menu bar popover shows. Only exists
/// on demand; closing it leaves the app running in the menu bar as usual.
@MainActor
enum FallbackWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: MenuBarView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "DropDrive"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
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

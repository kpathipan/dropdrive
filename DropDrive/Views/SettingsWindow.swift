import AppKit
import SwiftUI

/// Preferences are intentionally a normal resizable window: the menu-bar
/// popover is for the next download decision, while settings are infrequent,
/// longer-lived controls that benefit from room to read their descriptions.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PreferencesView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = tr("DropDrive Settings", "การตั้งค่า DropDrive")
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.setContentSize(NSSize(width: 520, height: 620))
            newWindow.minSize = NSSize(width: 460, height: 420)
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

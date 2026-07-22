import AppKit

/// Presents confirmations as real `NSAlert` panels rather than SwiftUI `.alert`
/// modifiers.
///
/// An alert attached to a view inside the menu bar popover only accepts clicks
/// while that popover's window is key — and this app is an `LSUIElement` agent,
/// so whenever another app holds focus the alert renders but ignores every
/// click, leaving the user staring at buttons that do nothing. Observed with the
/// restore-queue prompt. `NSAlert` brings the app forward and runs its own modal
/// session, which has no such dependency.
@MainActor
enum SystemAlert {
    /// Returns true when the user picked the first (default) button.
    @discardableResult
    static func confirm(
        title: String,
        message: String,
        confirmTitle: String,
        cancelTitle: String,
        destructive: Bool = false
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let confirm = alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: cancelTitle)
        if destructive {
            confirm.hasDestructiveAction = true
        }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func inform(title: String, message: String, confirmTitle: String, secondaryTitle: String? = nil) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        if let secondaryTitle {
            alert.addButton(withTitle: secondaryTitle)
        }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}

import SwiftUI

/// Enables AppKit's native frame autosave so window size and position persist
/// across launches without any custom UserDefaults plumbing.
struct WindowAccessor: NSViewRepresentable {
    /// Shared by ContentView (to tag the window) and MenuBarView (to find it again
    /// instead of opening a duplicate) — keep both call sites in sync with this.
    static let mainWindowAutosaveName = "DropDriveMainWindow"

    let autosaveName: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.setFrameAutosaveName(autosaveName)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

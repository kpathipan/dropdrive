import SwiftUI

@main
struct DropDriveApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About DropDrive") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.applicationName: "DropDrive",
                            NSApplication.AboutPanelOptionKey.applicationVersion: "1.0.0 Beta",
                            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                                string: "Download Google Drive files and folders directly to your Mac.",
                                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
                            )
                        ]
                    )
                }
            }
        }
    }
}

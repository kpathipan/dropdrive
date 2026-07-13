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
                            NSApplication.AboutPanelOptionKey.applicationVersion: "2.0.0 Development",
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

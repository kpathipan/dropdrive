import SwiftUI
import UserNotifications

@main
struct DropDriveApp: App {
    // Set this once a public repository exists, e.g. URL(string: "https://github.com/yourorg/dropdrive")
    private static let githubURL: URL? = nil

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationService.requestAuthorizationIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
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
    }

    private func showAboutPanel() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        let credits = NSMutableAttributedString(
            string: "Download Google Drive files and folders directly to your Mac.\n\nBuild \(build)\nLicense: All Rights Reserved",
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
                NSApplication.AboutPanelOptionKey.applicationVersion: "2.0.1 Development",
                NSApplication.AboutPanelOptionKey.credits: credits
            ]
        )
    }
}

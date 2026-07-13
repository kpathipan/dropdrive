import SwiftUI
import UserNotifications

@main
struct DropDriveApp: App {
    // Set this once a public repository exists, e.g. URL(string: "https://github.com/yourorg/dropdrive")
    private static let githubURL: URL? = nil

    private static let mainWindowID = "main"

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var historyStore = DownloadHistoryStore.shared

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
            Button("Open DropDrive") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: Self.mainWindowID)
            }

            recentDownloadsMenu

            Divider()

            Button("Preferences…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit DropDrive") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    @ViewBuilder
    private var recentDownloadsMenu: some View {
        Menu("Recent Downloads") {
            if historyStore.items.isEmpty {
                Text("No Recent Downloads")
            } else {
                ForEach(historyStore.items.prefix(5)) { item in
                    Button(item.name) {
                        guard let url = item.itemURL else { return }
                        NSApp.activate(ignoringOtherApps: true)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .disabled(item.itemURL == nil)
                }
            }
        }
    }

    private func showAboutPanel() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "4.0.0"

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
                NSApplication.AboutPanelOptionKey.applicationVersion: "\(version) Development",
                NSApplication.AboutPanelOptionKey.credits: credits
            ]
        )
    }
}

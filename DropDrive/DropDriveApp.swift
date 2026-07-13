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
    @State private var pendingDeepLinkURL: URL?

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

    private func handleDeepLink(_ url: URL) {
        // Handle dropdrive://download?url=<share-link>
        guard url.scheme == "dropdrive" else { return }
        guard url.host == "download" else { return }

        // Extract URL query parameter
        guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = urlComponents.queryItems,
              let urlItem = queryItems.first(where: { $0.name == "url" }),
              let downloadURLString = urlItem.value,
              !downloadURLString.isEmpty else {
            return
        }

        // Bring app to front and set the deep link URL for ContentView to process
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: Self.mainWindowID)
        pendingDeepLinkURL = URL(string: downloadURLString)
    }
}

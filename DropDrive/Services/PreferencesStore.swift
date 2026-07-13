import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class PreferencesStore {
    static let shared = PreferencesStore()

    private enum Key {
        static let defaultDownloadFolderBookmark = "preferences.defaultDownloadFolderBookmark"
        static let openFinderWhenComplete = "preferences.openFinderWhenComplete"
        static let playNotificationSound = "preferences.playNotificationSound"
        static let launchAtLogin = "preferences.launchAtLogin"
    }

    var defaultDownloadFolderURL: URL? {
        didSet { saveDefaultDownloadFolder() }
    }

    var openFinderWhenComplete: Bool {
        didSet { UserDefaults.standard.set(openFinderWhenComplete, forKey: Key.openFinderWhenComplete) }
    }

    var playNotificationSound: Bool {
        didSet { UserDefaults.standard.set(playNotificationSound, forKey: Key.playNotificationSound) }
    }

    /// Disabled by default; toggling this registers/unregisters the app with
    /// SMAppService rather than just flipping a stored flag.
    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            UserDefaults.standard.set(launchAtLogin, forKey: Key.launchAtLogin)
            applyLaunchAtLogin()
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        openFinderWhenComplete = defaults.bool(forKey: Key.openFinderWhenComplete)
        playNotificationSound = defaults.object(forKey: Key.playNotificationSound) as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        defaultDownloadFolderURL = Self.restoreDefaultDownloadFolder()
    }

    func setDefaultDownloadFolder(_ url: URL?) {
        defaultDownloadFolderURL = url
    }

    private func saveDefaultDownloadFolder() {
        guard let url = defaultDownloadFolderURL else {
            SecurityScopedBookmark.clear(forKey: Key.defaultDownloadFolderBookmark)
            return
        }

        SecurityScopedBookmark.save(url, forKey: Key.defaultDownloadFolderBookmark)
    }

    private static func restoreDefaultDownloadFolder() -> URL? {
        SecurityScopedBookmark.restore(forKey: Key.defaultDownloadFolderBookmark)
    }

    /// Reflects the actual SMAppService registration state, which is the source of
    /// truth macOS uses (e.g. if the user removed DropDrive from Login Items directly).
    func syncLaunchAtLoginWithSystemState() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Registration can fail (e.g. outside a signed .app bundle during
            // development); fall back to reflecting the real system state.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

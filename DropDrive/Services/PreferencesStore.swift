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
        static let bandwidthLimitBytesPerSecond = "preferences.bandwidthLimitBytesPerSecond"
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

    /// nil means unlimited. Applied immediately to the process-wide throttle so an
    /// in-progress download reacts to the change right away.
    var bandwidthLimitBytesPerSecond: Double? {
        didSet {
            guard bandwidthLimitBytesPerSecond != oldValue else { return }
            if let bandwidthLimitBytesPerSecond {
                UserDefaults.standard.set(bandwidthLimitBytesPerSecond, forKey: Key.bandwidthLimitBytesPerSecond)
            } else {
                UserDefaults.standard.removeObject(forKey: Key.bandwidthLimitBytesPerSecond)
            }
            BandwidthLimiter.shared.setLimit(bytesPerSecond: bandwidthLimitBytesPerSecond)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        openFinderWhenComplete = defaults.bool(forKey: Key.openFinderWhenComplete)
        playNotificationSound = defaults.object(forKey: Key.playNotificationSound) as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        defaultDownloadFolderURL = Self.restoreDefaultDownloadFolder()
        let storedLimit = defaults.object(forKey: Key.bandwidthLimitBytesPerSecond) as? Double
        bandwidthLimitBytesPerSecond = storedLimit
        BandwidthLimiter.shared.setLimit(bytesPerSecond: storedLimit)
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

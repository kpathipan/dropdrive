import AppKit
import Foundation
import Observation

/// In-app theme switch: follow the system appearance, or pin light/dark.
/// `DDTheme`'s colors read `isDark` through Observation, so every view using
/// them re-renders the moment the mode (or the system appearance) changes.
@Observable
final class AppTheme {
    static let shared = AppTheme()

    static let system = "system"
    static let light = "light"
    static let dark = "dark"

    var mode: String {
        didSet { UserDefaults.standard.set(mode, forKey: Self.defaultsKey) }
    }

    /// Tracked separately so "system" mode updates live when macOS switches
    /// appearance (the distributed notification fires on every toggle).
    private(set) var systemIsDark: Bool

    var isDark: Bool {
        switch mode {
        case Self.dark: true
        case Self.light: false
        default: systemIsDark
        }
    }

    private static let defaultsKey = "appThemeMode"

    private init() {
        mode = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? Self.system
        systemIsDark = Self.currentSystemIsDark()

        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue by the `queue: .main` above, but the
            // closure itself is `@Sendable`, so the isolation has to be stated
            // rather than assumed.
            MainActor.assumeIsolated {
                self?.systemIsDark = Self.currentSystemIsDark()
            }
        }
    }

    private static func currentSystemIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
}

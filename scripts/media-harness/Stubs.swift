import Foundation

func tr(_ english: String, _ thai: String) -> String { english }
@MainActor final class PreferencesStore {
    static let shared = PreferencesStore()
    var preferCompatibleVideo = true
    var bandwidthLimitBytesPerSecond: Double? = 1024 * 1024
}

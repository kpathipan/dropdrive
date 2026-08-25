import Foundation

/// Normalizes destination availability across local, removable, and network
/// volumes. Some SMB/NAS volumes report `0` for
/// `volumeAvailableCapacityForImportantUsage` when the value is unavailable;
/// zero is therefore "unknown", not proof that the disk is full.
nonisolated enum DestinationCapacity {
    enum State: Equatable, Sendable {
        case notSelected
        case unavailable
        case unknown
        case available(Int64)
    }

    static func inspect(_ url: URL?) -> State {
        guard let url else { return .notSelected }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .unavailable
        }

        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return .unknown }
        return normalized(
            important: values.volumeAvailableCapacityForImportantUsage,
            ordinary: values.volumeAvailableCapacity.map(Int64.init)
        )
    }

    /// Kept pure so the NAS/SMB zero-capacity regression can be tested without
    /// depending on a particular mounted volume.
    static func normalized(important: Int64?, ordinary: Int64?) -> State {
        let candidates = [important, ordinary].compactMap { $0 }.filter { $0 > 0 }
        guard let best = candidates.max() else { return .unknown }
        return .available(best)
    }
}

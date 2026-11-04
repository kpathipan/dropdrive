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

/// A resumed folder only needs room for its pending files. Its actual plan is
/// owned by the download service, so the view model must defer the full budget
/// until that service has separated completed files from pending work.
nonisolated enum DownloadSpaceBudget {
    static let reserveBytes: Int64 = 64 * 1024 * 1024

    static func required(forRemainingBytes bytes: Int64) -> Int64 {
        let bytes = max(0, bytes)
        let headroom = min(Int64(2 * 1024 * 1024 * 1024), max(reserveBytes, bytes / 10))
        let result = bytes.addingReportingOverflow(headroom)
        return result.overflow ? Int64.max : result.partialValue
    }

    static func beforePlanning(totalBytes: Int64?, isFolder: Bool, isVideo: Bool) -> Int64 {
        if isFolder || isVideo { return reserveBytes }
        return totalBytes.map(required(forRemainingBytes:)) ?? reserveBytes
    }
}

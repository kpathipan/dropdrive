import Foundation

/// Sweeps up scratch files that a previous run left behind.
///
/// Multi-part downloads stage their byte ranges in `DropDrive-<uuid>` temp
/// directories and delete them on the way out, but that cleanup never runs when
/// the process is killed mid-download (force quit, crash, restart). Each
/// abandoned attempt then strands its parts — observed in the wild at 20 leftover
/// directories holding 14 GB, which is what filled the user's disk.
nonisolated enum TempCleaner {
    /// Directories younger than this may belong to a download still running in
    /// another instance, so they're left alone.
    private static let minimumAge: TimeInterval = 60 * 60

    static func sweepInBackground() {
        Task.detached(priority: .utility) {
            sweep()
        }
    }

    static func sweep() {
        let fileManager = FileManager.default
        let temp = fileManager.temporaryDirectory
        let entries = (try? fileManager.contentsOfDirectory(
            at: temp,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let cutoff = Date().addingTimeInterval(-minimumAge)

        for entry in entries {
            let name = entry.lastPathComponent
            // Only our own scratch: the multi-part staging dirs and the cached
            // yt-dlp extraction info.
            guard name.hasPrefix("DropDrive-") || name == "DropDrive-info" else { continue }

            let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modified = values?.contentModificationDate, modified < cutoff else { continue }

            try? fileManager.removeItem(at: entry)
        }
    }
}

import Foundation

/// Only disposable files in exact app-owned cache directories are swept.
/// System downloads and unknown staging directories are never ours by name alone.
nonisolated enum TempCleaner {
    static func sweepInBackground() {
        Task.detached(priority: .utility) { sweep() }
    }

    static func sweep(in temporary: URL = FileManager.default.temporaryDirectory, now: Date = .now) {
        let manager = FileManager.default
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        for name in ["DropDrive-info", "dropdrive-ytdlp-cache"] {
            let directory = temporary.appendingPathComponent(name, isDirectory: true)
            guard let values = try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]),
                values.isSymbolicLink != true,
                let enumerator = manager.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles])
            else { continue }
            for case let file as URL in enumerator {
                guard
                    let values = try? file.resourceValues(forKeys: [
                        .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey,
                    ]),
                    values.isSymbolicLink != true, values.isRegularFile == true,
                    let modified = values.contentModificationDate, modified < cutoff
                else { continue }
                try? manager.removeItem(at: file)
            }
        }
    }
}

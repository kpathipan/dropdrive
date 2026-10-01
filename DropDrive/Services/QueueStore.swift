import Foundation

/// Persists the download queue across launches so an interrupted session can resume.
enum QueueStore {
    private static let key = "downloadQueue"
    private static let disk = QueueDiskStore(directory: FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DropDrive", isDirectory: true))

    static func save(_ items: [QueueItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        do { try disk.save(data) }
        catch { NSLog("DropDrive: queue checkpoint write failed: %@", error.localizedDescription) }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Returns nil if nothing was ever saved, or an empty array if the last saved
    /// queue was empty — callers use nil to decide whether a restore prompt is needed.
    static func load() -> [QueueItem]? {
        if let items = disk.load() { return items }
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        guard let items = try? JSONDecoder().decode([QueueItem].self, from: data) else { return nil }
        try? disk.save(data)
        return items
    }

    static func clear() {
        // Persist an explicit empty queue, so an older backup cannot resurrect
        // work that the user discarded or that has already completed.
        save([])
    }
}

/// Atomic on-disk checkpoints survive a forced process exit without waiting for
/// cfprefsd to flush UserDefaults. A single last-good backup covers corruption.
struct QueueDiskStore {
    let directory: URL
    private var current: URL { directory.appendingPathComponent("queue-v1.json") }
    private var backup: URL { directory.appendingPathComponent("queue-v1.previous.json") }

    func save(_ data: Data) throws {
        _ = try JSONDecoder().decode([QueueItem].self, from: data)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let previous = try? Data(contentsOf: current),
           (try? JSONDecoder().decode([QueueItem].self, from: previous)) != nil {
            try previous.write(to: backup, options: .atomic)
        }
        try data.write(to: current, options: .atomic)
    }

    func load() -> [QueueItem]? {
        for url in [current, backup] {
            if let data = try? Data(contentsOf: url),
               let items = try? JSONDecoder().decode([QueueItem].self, from: data) { return items }
        }
        return nil
    }
}

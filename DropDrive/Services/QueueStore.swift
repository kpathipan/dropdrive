import Foundation

/// Persists the download queue across launches so an interrupted session can resume.
enum QueueStore {
    private static let key = "downloadQueue"

    static func save(_ items: [QueueItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Returns nil if nothing was ever saved, or an empty array if the last saved
    /// queue was empty — callers use nil to decide whether a restore prompt is needed.
    static func load() -> [QueueItem]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([QueueItem].self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

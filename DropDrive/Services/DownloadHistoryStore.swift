import Foundation
import Observation

/// Shared across the main window and the menu bar extra, so both reflect the same
/// history without needing a common view hierarchy.
@MainActor
@Observable
final class DownloadHistoryStore {
    static let shared = DownloadHistoryStore()

    /// UserDefaults isn't meant for large datasets; keep only the most recent entries.
    private static let maxItems = 50
    private static let storageKey = "downloadHistory"

    private(set) var items: [DownloadHistoryItem] = []

    private init() {
        items = Self.load()
    }

    func record(_ item: DownloadHistoryItem) {
        items.insert(item, at: 0)
        if items.count > Self.maxItems {
            items.removeLast(items.count - Self.maxItems)
        }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func load() -> [DownloadHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([DownloadHistoryItem].self, from: data) else {
            return []
        }
        return items
    }
}

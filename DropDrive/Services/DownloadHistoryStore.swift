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

    /// Rollups the UI reads on every redraw — the header's "N today", the
    /// Statistics pane's three totals. Derived once when the list changes
    /// instead of re-filtering and re-reducing the whole history each time a
    /// progress tick redraws the window.
    struct Totals {
        var completedCount = 0
        var completedToday = 0
        var totalFiles = 0
        var totalBytes: Int64 = 0
    }

    private(set) var totals = Totals()

    private init() {
        items = Self.load()
        recomputeTotals()
    }

    func record(_ item: DownloadHistoryItem) {
        items.insert(item, at: 0)
        if items.count > Self.maxItems {
            items.removeLast(items.count - Self.maxItems)
        }
        recomputeTotals()
        save()
    }

    func clear() {
        items = []
        recomputeTotals()
        save()
    }

    private func recomputeTotals() {
        let calendar = Calendar.current
        var next = Totals()
        for item in items where item.status == .completed {
            next.completedCount += 1
            next.totalFiles += item.fileCount ?? 1
            next.totalBytes += item.sizeBytes ?? 0
            if calendar.isDateInToday(item.date) { next.completedToday += 1 }
        }
        totals = next
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

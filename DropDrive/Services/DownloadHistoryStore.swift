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
    private static let lifetimeKey = "downloadHistoryLifetimeTotals.v1"
    private static let identitiesKey = "downloadHistoryCompletedIdentities.v1"
    private static let maximumCompletedIdentities = 1_000

    private(set) var items: [DownloadHistoryItem] = []

    /// Rollups the UI reads on every redraw — the header's "N today", the
    /// Statistics pane's three totals. Derived once when the list changes
    /// instead of re-filtering and re-reducing the whole history each time a
    /// progress tick redraws the window.
    struct Totals: Equatable {
        var completedCount = 0
        var completedToday = 0
        var totalFiles = 0
        var totalBytes: Int64 = 0
    }

    private(set) var totals = Totals()
    private var lifetime = LifetimeTotals()
    private var completedIdentities: [String] = []

    private struct LifetimeTotals: Codable {
        var completedCount = 0
        var totalFiles = 0
        var totalBytes: Int64 = 0
        var dayStart = Calendar.current.startOfDay(for: .now)
        var completedToday = 0
    }

    /// `completedToday` is the one rollup that goes stale on its own: the app
    /// sits in the menu bar for days at a time, so without this the header would
    /// still be reporting yesterday's count at breakfast.
    private var midnightTask: Task<Void, Never>?

    private init() {
        items = Self.load()
        if let stored = Self.loadLifetime() {
            lifetime = stored
        } else {
            lifetime = Self.migrateLifetime(from: items)
            saveLifetime()
        }
        completedIdentities = Self.loadIdentities()
        if completedIdentities.isEmpty {
            completedIdentities = Self.migrateIdentities(from: items)
            saveIdentities()
        }
        refreshTotals()
    }

    func record(_ item: DownloadHistoryItem) {
        items.insert(item, at: 0)
        if items.count > Self.maxItems {
            items.removeLast(items.count - Self.maxItems)
        }
        if item.status == .completed {
            rollDayForwardIfNeeded()
            lifetime.completedCount += 1
            lifetime.completedToday += 1
            lifetime.totalFiles += item.fileCount ?? 1
            lifetime.totalBytes += item.sizeBytes ?? 0
            if let identity = Self.identity(for: item.driveLink) {
                completedIdentities.removeAll { $0 == identity }
                completedIdentities.insert(identity, at: 0)
                if completedIdentities.count > Self.maximumCompletedIdentities {
                    completedIdentities.removeLast(completedIdentities.count - Self.maximumCompletedIdentities)
                }
                saveIdentities()
            }
            saveLifetime()
        }
        refreshTotals()
        save()
    }

    /// Duplicate protection is intentionally wider than the 50 visible recent
    /// rows. Trimming UI history must not make older downloads look new again.
    func hasCompleted(itemID: String) -> Bool {
        completedIdentities.contains(itemID)
    }

    /// Drops one entry. History accumulates items whose files the user has since
    /// moved or deleted, and wiping the lot was the only way to tidy up.
    func remove(_ item: DownloadHistoryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func refreshTotals() {
        rollDayForwardIfNeeded()
        totals = Totals(
            completedCount: lifetime.completedCount,
            completedToday: lifetime.completedToday,
            totalFiles: lifetime.totalFiles,
            totalBytes: lifetime.totalBytes
        )
        scheduleMidnightRefresh()
    }

    private func rollDayForwardIfNeeded() {
        let today = Calendar.current.startOfDay(for: .now)
        guard lifetime.dayStart != today else { return }
        lifetime.dayStart = today
        lifetime.completedToday = 0
        saveLifetime()
    }

    private func scheduleMidnightRefresh() {
        midnightTask?.cancel()
        let calendar = Calendar.current
        guard let midnight = calendar.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 0, second: 5),
            matchingPolicy: .nextTime
        ) else { return }

        let interval = midnight.timeIntervalSinceNow
        guard interval > 0 else { return }
        midnightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self?.refreshTotals()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func saveLifetime() {
        guard let data = try? JSONEncoder().encode(lifetime) else { return }
        UserDefaults.standard.set(data, forKey: Self.lifetimeKey)
    }

    private func saveIdentities() {
        UserDefaults.standard.set(completedIdentities, forKey: Self.identitiesKey)
    }

    private static func load() -> [DownloadHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([DownloadHistoryItem].self, from: data) else {
            return []
        }
        return items
    }

    private static func loadLifetime() -> LifetimeTotals? {
        guard let data = UserDefaults.standard.data(forKey: lifetimeKey) else { return nil }
        return try? JSONDecoder().decode(LifetimeTotals.self, from: data)
    }

    private static func loadIdentities() -> [String] {
        UserDefaults.standard.stringArray(forKey: identitiesKey) ?? []
    }

    private static func migrateLifetime(from items: [DownloadHistoryItem]) -> LifetimeTotals {
        var migrated = LifetimeTotals()
        for item in items where item.status == .completed {
            migrated.completedCount += 1
            migrated.totalFiles += item.fileCount ?? 1
            migrated.totalBytes += item.sizeBytes ?? 0
            if Calendar.current.isDateInToday(item.date) { migrated.completedToday += 1 }
        }
        return migrated
    }

    private static func migrateIdentities(from items: [DownloadHistoryItem]) -> [String] {
        var seen: Set<String> = []
        return items.compactMap { item in
            guard item.status == .completed,
                  let identity = identity(for: item.driveLink),
                  seen.insert(identity).inserted else { return nil }
            return identity
        }
    }

    private static func identity(for link: String) -> String? {
        if let driveID = GoogleDriveLinkParser.itemID(from: link) { return driveID }
        guard VideoDownloadService.isSupportedLink(link) else { return nil }
        return LinkIdentity.videoItemID(for: link)
    }
}

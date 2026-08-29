import Foundation
import Observation

/// A bounded receipt of playlist/carousel entries already completed. It stores
/// identifiers only—never media or extractor JSON—so "select new" is instant
/// without turning DropDrive into a second library database.
@MainActor
@Observable
final class MediaCollectionSnapshotStore {
    static let shared = MediaCollectionSnapshotStore()

    private struct Snapshot: Codable {
        var updatedAt: Date
        var itemIDs: Set<String>
    }

    private static let maximumCollections = 12
    private static let maximumItems = 10_000
    private var snapshots: [String: Snapshot]

    private init() { snapshots = Self.load() }

    func hasHistory(collectionID: String) -> Bool { snapshots[collectionID] != nil }

    func isNew(collectionID: String, item: DriveLinkAnalysis.MediaItem) -> Bool {
        guard let snapshot = snapshots[collectionID] else { return false }
        return !snapshot.itemIDs.contains(item.id)
    }

    func newIndexes(collectionID: String, items: [DriveLinkAnalysis.MediaItem]) -> Set<Int> {
        guard let snapshot = snapshots[collectionID] else { return Set(items.map(\.index)) }
        return Set(items.filter { !snapshot.itemIDs.contains($0.id) }.map(\.index))
    }

    func recordCompleted(
        collectionID: String,
        items: [DriveLinkAnalysis.MediaItem],
        selectedIndexes: Set<Int>?
    ) {
        let completed = selectedIndexes.map { selected in items.filter { selected.contains($0.index) } } ?? items
        var snapshot = snapshots[collectionID] ?? Snapshot(updatedAt: .now, itemIDs: [])
        snapshot.updatedAt = .now
        snapshot.itemIDs.formUnion(completed.map(\.id))
        if snapshot.itemIDs.count > Self.maximumItems {
            snapshot.itemIDs = Set(snapshot.itemIDs.sorted().prefix(Self.maximumItems))
        }
        snapshots[collectionID] = snapshot
        trimAndSave()
    }

    private func trimAndSave() {
        if snapshots.count > Self.maximumCollections {
            snapshots = Dictionary(uniqueKeysWithValues: snapshots
                .sorted { $0.value.updatedAt > $1.value.updatedAt }
                .prefix(Self.maximumCollections)
                .map { ($0.key, $0.value) })
        }
        guard let data = try? JSONEncoder().encode(snapshots), let url = Self.storageURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static var storageURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DropDrive", isDirectory: true)
            .appendingPathComponent("media-collections-v1.json")
    }

    private static func load() -> [String: Snapshot] {
        guard let url = storageURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Snapshot].self, from: data)
        else { return [:] }
        return decoded
    }
}

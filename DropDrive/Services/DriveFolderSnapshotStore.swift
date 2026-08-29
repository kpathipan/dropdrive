import Foundation
import Observation

/// Remembers only source fingerprints for recently downloaded Drive folders.
/// This powers "new / changed / downloaded" badges without retaining a second
/// file copy or the full analysis manifest. One bounded JSON file is replaced
/// atomically after a completed folder download.
@MainActor
@Observable
final class DriveFolderSnapshotStore {
    static let shared = DriveFolderSnapshotStore()

    enum ItemState: Equatable {
        case new
        case changed
        case downloaded
        case unknown
    }

    struct Summary: Equatable {
        var newCount = 0
        var changedCount = 0
        var downloadedCount = 0

        var hasHistory: Bool { changedCount + downloadedCount > 0 }
    }

    private struct Snapshot: Codable {
        var updatedAt: Date
        var files: [String: String]
    }

    private static let maximumFolders = 12
    private static let maximumItemsPerFolder = 10_000
    private var snapshots: [String: Snapshot]

    private init() {
        snapshots = Self.load()
    }

    func state(folderID: String, item: DriveLinkAnalysis.FolderItem) -> ItemState {
        guard let snapshot = snapshots[folderID] else { return .unknown }
        guard let oldFingerprint = snapshot.files[item.id] else { return .new }
        return oldFingerprint == Self.fingerprint(item) ? .downloaded : .changed
    }

    func summary(folderID: String, items: [DriveLinkAnalysis.FolderItem]) -> Summary {
        guard snapshots[folderID] != nil else { return Summary() }
        return items.reduce(into: Summary()) { result, item in
            switch state(folderID: folderID, item: item) {
            case .new: result.newCount += 1
            case .changed: result.changedCount += 1
            case .downloaded: result.downloadedCount += 1
            case .unknown: break
            }
        }
    }

    func newOrChangedIDs(folderID: String, items: [DriveLinkAnalysis.FolderItem]) -> Set<String> {
        Set(items.compactMap { item in
            switch state(folderID: folderID, item: item) {
            case .new, .changed: item.id
            case .downloaded, .unknown: nil
            }
        })
    }

    /// A full-folder download replaces the snapshot. A partial download merges
    /// only the selected rows so unselected files never become "downloaded".
    func recordCompletedFolder(_ analysis: DriveLinkAnalysis, selectedIDs: Set<String>?) {
        guard analysis.type == .folder, let items = analysis.folderItems else { return }
        let ordered = items.sorted { $0.id < $1.id }
        let selected = selectedIDs.map { ids in ordered.filter { ids.contains($0.id) } } ?? ordered
        let bounded = Array(selected.prefix(Self.maximumItemsPerFolder))
        let recorded = Dictionary(uniqueKeysWithValues: bounded.map { ($0.id, Self.fingerprint($0)) })

        if selectedIDs == nil {
            snapshots[analysis.itemID] = Snapshot(updatedAt: .now, files: recorded)
        } else {
            var snapshot = snapshots[analysis.itemID] ?? Snapshot(updatedAt: .now, files: [:])
            snapshot.updatedAt = .now
            snapshot.files.merge(recorded) { _, newest in newest }
            if snapshot.files.count > Self.maximumItemsPerFolder {
                snapshot.files = Dictionary(uniqueKeysWithValues:
                    snapshot.files.sorted { $0.key < $1.key }
                        .prefix(Self.maximumItemsPerFolder)
                        .map { ($0.key, $0.value) }
                )
            }
            snapshots[analysis.itemID] = snapshot
        }

        trimAndSave()
    }

    private func trimAndSave() {
        if snapshots.count > Self.maximumFolders {
            let keep = snapshots.sorted { $0.value.updatedAt > $1.value.updatedAt }
                .prefix(Self.maximumFolders)
            snapshots = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        guard let data = try? JSONEncoder().encode(snapshots), let url = Self.storageURL else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func fingerprint(_ item: DriveLinkAnalysis.FolderItem) -> String {
        if let checksum = item.md5Checksum { return "md5:\(checksum)" }
        if let modified = item.modifiedTime { return "modified:\(modified)" }
        if let version = item.thumbnailVersion { return "thumbnail:\(version)" }
        return "fallback:\(item.mimeType):\(item.size ?? -1):\(item.name)"
    }

    private static var storageURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DropDrive", isDirectory: true)
            .appendingPathComponent("folder-snapshots-v1.json")
    }

    private static func load() -> [String: Snapshot] {
        guard let url = storageURL,
              let data = try? Data(contentsOf: url),
              let snapshots = try? JSONDecoder().decode([String: Snapshot].self, from: data)
        else { return [:] }
        return snapshots
    }
}

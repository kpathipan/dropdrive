import AppKit
import Foundation
import Observation

/// Downloads the short-lived artwork Google Drive already generated for an
/// item. Only compressed image bytes are cached, with a hard memory budget; no
/// thumbnail files are written to disk.
actor DriveThumbnailCache {
    static let shared = DriveThumbnailCache()

    private static let maximumBytes = 24 * 1024 * 1024
    private static let maximumItemBytes = 8 * 1024 * 1024
    /// An ephemeral session is intentional: `URLSession.shared` may place
    /// responses in its on-disk URL cache even when our own cache is memory-only.
    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()
    private var storage: [String: Data] = [:]
    private var insertionOrder: [String] = []
    private var totalBytes = 0
    private var inFlight: [String: Task<Data?, Never>] = [:]

    private func key(for item: DriveLinkAnalysis.FolderItem) -> String {
        "\(item.id):\(item.thumbnailVersion ?? "current")"
    }

    func data(for item: DriveLinkAnalysis.FolderItem) async -> Data? {
        guard item.category == .images || item.category == .videos,
              item.thumbnailLink != nil else { return nil }

        let key = key(for: item)
        if let cached = storage[key] { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<Data?, Never> { await Self.fetch(item) }
        inFlight[key] = task
        let data = await task.value
        inFlight[key] = nil
        if let data { store(data, for: key) }
        return data
    }

    private func store(_ data: Data, for key: String) {
        if let old = storage[key] {
            totalBytes -= old.count
        } else {
            insertionOrder.append(key)
        }
        storage[key] = data
        totalBytes += data.count

        while totalBytes > Self.maximumBytes, let oldest = insertionOrder.first {
            insertionOrder.removeFirst()
            if let removed = storage.removeValue(forKey: oldest) {
                totalBytes -= removed.count
            }
        }
    }

    private nonisolated static func fetch(_ item: DriveLinkAnalysis.FolderItem) async -> Data? {
        guard let raw = item.thumbnailLink, let url = URL(string: raw) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // Public thumbnails work without a token. Supplying the existing Drive
        // token also covers private files without creating a second login path.
        if let token = await LoginManager.shared.cachedAccessTokenIfAvailable() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let resourceKey = item.resourceKey {
            request.setValue("\(item.id)/\(resourceKey)", forHTTPHeaderField: "X-Goog-Drive-Resource-Keys")
        }

        guard let (data, response) = try? await Self.session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty,
              data.count <= Self.maximumItemBytes else { return nil }
        return data
    }
}

/// One observable request per visible tile. Lazy containers create these only
/// for on-screen items, while the cache deduplicates a thumbnail shared by a
/// card and its Space-bar preview.
@MainActor
@Observable
final class DriveThumbnailModel {
    var image: NSImage?
    var isLoading = false

    private var requestKey = ""
    private var task: Task<Void, Never>?

    func load(item: DriveLinkAnalysis.FolderItem) {
        let key = "\(item.id):\(item.thumbnailVersion ?? "current")"
        guard key != requestKey else { return }
        requestKey = key
        task?.cancel()
        image = nil
        isLoading = item.thumbnailLink != nil
        task = Task {
            let data = await DriveThumbnailCache.shared.data(for: item)
            guard !Task.isCancelled, key == requestKey else { return }
            image = data.flatMap(NSImage.init(data:))
            isLoading = false
        }
    }
}

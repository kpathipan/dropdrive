import AppKit
import QuickLookThumbnailing

/// Generates and caches Quick Look thumbnails for downloaded files — the same
/// previews Finder shows (real video frames, image contents, PDF first pages),
/// no stored artwork of our own. SwiftUI views observe a single request through
/// `ThumbnailModel`; the shared actor dedupes work and caches by path+size.
actor Thumbnailer {
    static let shared = Thumbnailer()

    /// Decoded thumbnails are full bitmaps; a long session browsing a big
    /// history would otherwise hold every one it ever generated.
    private static let cacheCapacity = 200

    private var cache: [String: NSImage] = [:]
    private var cacheOrder: [String] = []
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    private func key(_ url: URL, _ side: CGFloat) -> String {
        "\(url.path)|\(Int(side))"
    }

    private func store(_ image: NSImage, for key: String) {
        if cache.index(forKey: key) == nil {
            cacheOrder.append(key)
        }
        cache[key] = image
        while cacheOrder.count > Self.cacheCapacity {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    func thumbnail(for url: URL, side: CGFloat) async -> NSImage? {
        let key = key(url, side)
        if let cached = cache[key] { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<NSImage?, Never> { [scale = NSScreen.main?.backingScaleFactor ?? 2] in
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: side, height: side),
                scale: scale,
                representationTypes: .thumbnail
            )
            let generated = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return generated.map { NSImage(cgImage: $0.cgImage, size: .zero) }
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { store(image, for: key) }
        return image
    }

    /// Every regular file directly inside a folder, sorted by name.
    ///
    /// Actor-isolated rather than `nonisolated` on purpose: its callers are
    /// SwiftUI `.task` blocks, which run on the main actor, so a `nonisolated`
    /// version did its directory read and its per-file `resourceValues` calls on
    /// the main thread — a visible stall for a folder with many files, and worse
    /// on a network or iCloud volume.
    func files(in folderURL: URL, limit: Int? = nil) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let sorted = contents
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }

    /// The first few files inside a folder, for its 2×2 cover collage.
    func coverCandidates(in folderURL: URL, limit: Int = 4) -> [URL] {
        files(in: folderURL, limit: limit)
    }
}

/// Observable single-thumbnail loader for a SwiftUI view. Loads on first
/// appearance and publishes the image when ready.
@MainActor
@Observable
final class ThumbnailModel {
    var image: NSImage?
    private var loaded = false

    func load(url: URL, side: CGFloat) {
        guard !loaded else { return }
        loaded = true
        Task {
            image = await Thumbnailer.shared.thumbnail(for: url, side: side)
        }
    }
}

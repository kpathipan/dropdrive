import AppKit
import QuickLookThumbnailing

/// Generates and caches Quick Look thumbnails for downloaded files — the same
/// previews Finder shows (real video frames, image contents, PDF first pages),
/// no stored artwork of our own. SwiftUI views observe a single request through
/// `ThumbnailModel`; the shared actor dedupes work and caches by path+size.
actor Thumbnailer {
    static let shared = Thumbnailer()

    private var cache: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    private func key(_ url: URL, _ side: CGFloat) -> String {
        "\(url.path)|\(Int(side))"
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
        if let image { cache[key] = image }
        return image
    }

    /// The first few file URLs directly inside a folder, sorted, for a 2×2 cover
    /// collage. Directories are skipped so the cover shows actual media.
    nonisolated func coverCandidates(in folderURL: URL, limit: Int = 4) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(limit)
            .map { $0 }
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

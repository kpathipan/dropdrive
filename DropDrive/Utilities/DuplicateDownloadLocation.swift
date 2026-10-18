import Foundation

/// Uses recorded output paths, never guesses from a title or scans the disk.
/// A duplicate identity can outlive its history row or a disconnected drive.
enum DuplicateDownloadLocation {
    static func existingURL(_ url: URL?) -> URL? {
        guard let url, url.isFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static func completedURL(
        itemID: String, queue: [QueueItem], history: [DownloadHistoryItem]
    ) -> URL? {
        for item in queue.reversed() where item.itemID == itemID && item.status == .completed {
            if let url = existingURL(item.resultURL) { return url }
        }
        // History is newest first. Skip missing outputs so an older copy can
        // still be revealed when the most recent one has been moved/deleted.
        for item in history where item.status == .completed {
            let identity = GoogleDriveLinkParser.itemID(from: item.driveLink)
                ?? LinkIdentity.videoItemID(for: item.driveLink)
            if identity == itemID, let url = existingURL(item.itemURL) { return url }
        }
        return nil
    }
}

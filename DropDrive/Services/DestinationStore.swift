import Foundation

enum DestinationStore {
    private static let bookmarkKey = "lastDestinationBookmark"

    static func save(_ url: URL) {
        SecurityScopedBookmark.save(url, forKey: bookmarkKey)
    }

    static func restore() -> URL? {
        SecurityScopedBookmark.restore(forKey: bookmarkKey)
    }
}

import Foundation

/// Shared save/restore logic for security-scoped folder bookmarks persisted in
/// UserDefaults. Used by both the last-used download destination and the
/// user's preferred default download folder.
enum SecurityScopedBookmark {
    static func save(_ url: URL, forKey key: String) {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }

        UserDefaults.standard.set(bookmark, forKey: key)
    }

    static func restore(forKey key: String) -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: key) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.startAccessingSecurityScopedResource() else {
            return nil
        }

        if isStale {
            save(url, forKey: key)
        }

        return url
    }

    static func clear(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

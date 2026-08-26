import Foundation

/// Shared save/restore logic for security-scoped folder bookmarks persisted in
/// UserDefaults. Used by both the last-used download destination and the
/// user's preferred default download folder.
enum SecurityScopedBookmark {
    private static func pathKey(for key: String) -> String { "\(key).path" }

    static func save(_ url: URL, forKey key: String) {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }

        UserDefaults.standard.set(bookmark, forKey: key)
        UserDefaults.standard.set(url.path, forKey: pathKey(for: key))
    }

    static func restore(forKey key: String) -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: key) else {
            return UserDefaults.standard.string(forKey: pathKey(for: key)).map(URL.init(fileURLWithPath:))
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return UserDefaults.standard.string(forKey: pathKey(for: key)).map(URL.init(fileURLWithPath:))
        }

        // A disconnected NAS can resolve its bookmark while refusing the
        // security scope. Keep the remembered URL visible; access is acquired
        // again when the volume mounts rather than turning it into "None".
        _ = SecurityScopedAccessManager.shared.retainAccess(to: url)
        UserDefaults.standard.set(url.path, forKey: pathKey(for: key))

        if isStale {
            save(url, forKey: key)
        }

        return url
    }

    static func clear(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: pathKey(for: key))
    }
}

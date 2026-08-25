import Foundation

enum DestinationStore {
    private static let bookmarkKey = "lastDestinationBookmark"
    private static let recentBookmarksKey = "recentDestinationBookmarks"
    private static let favoriteBookmarksKey = "favoriteDestinationBookmarks"
    private static let sourceRuleBookmarksKey = "destinationSourceRules"
    private static let maximumRecentDestinations = 5

    static func save(_ url: URL) {
        SecurityScopedBookmark.save(url, forKey: bookmarkKey)
        recordRecent(url)
    }

    static func restore() -> URL? {
        SecurityScopedBookmark.restore(forKey: bookmarkKey)
    }

    /// Security-scoped bookmarks are used for the destination chooser, so the
    /// quick menu keeps working after a relaunch instead of retaining paths the
    /// sandbox can no longer write to.
    static func recent() -> [URL] {
        restoreBookmarks(forKey: recentBookmarksKey)
    }

    static func favorites() -> [URL] {
        restoreBookmarks(forKey: favoriteBookmarksKey)
    }

    static func isFavorite(_ url: URL) -> Bool {
        favorites().contains { $0.standardizedFileURL == url.standardizedFileURL }
    }

    static func toggleFavorite(_ url: URL) {
        var urls = favorites()
        if let index = urls.firstIndex(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
            urls.remove(at: index)
        } else {
            urls.insert(url, at: 0)
        }
        saveBookmarks(urls, forKey: favoriteBookmarksKey)
    }

    /// A rule is source-based rather than a hidden filename guess. The user opts
    /// in from the review card, then that source consistently lands where they
    /// chose until the rule is removed.
    static func destinationRule(forLink link: String) -> URL? {
        guard let key = sourceKey(for: link),
              let rules = UserDefaults.standard.dictionary(forKey: sourceRuleBookmarksKey),
              let bookmark = rules[key] as? Data
        else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), SecurityScopedAccessManager.shared.retainAccess(to: url) else { return nil }
        return url
    }

    static func setDestinationRule(_ url: URL, forLink link: String) {
        guard let key = sourceKey(for: link),
              let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        var rules = UserDefaults.standard.dictionary(forKey: sourceRuleBookmarksKey) ?? [:]
        rules[key] = bookmark
        UserDefaults.standard.set(rules, forKey: sourceRuleBookmarksKey)
    }

    static func removeDestinationRule(forLink link: String) {
        guard let key = sourceKey(for: link) else { return }
        var rules = UserDefaults.standard.dictionary(forKey: sourceRuleBookmarksKey) ?? [:]
        rules.removeValue(forKey: key)
        UserDefaults.standard.set(rules, forKey: sourceRuleBookmarksKey)
    }

    static func sourceLabel(forLink link: String) -> String? {
        guard let key = sourceKey(for: link) else { return nil }
        switch key {
        case "youtube": return "YouTube"
        case "tiktok": return "TikTok"
        case "instagram": return "Instagram"
        case "facebook": return "Facebook"
        case "drive": return "Google Drive"
        default: return key
        }
    }

    private static func recordRecent(_ url: URL) {
        var urls = recent().filter { $0.standardizedFileURL != url.standardizedFileURL }
        urls.insert(url, at: 0)
        saveBookmarks(Array(urls.prefix(maximumRecentDestinations)), forKey: recentBookmarksKey)
    }

    private static func restoreBookmarks(forKey key: String) -> [URL] {
        guard let bookmarks = UserDefaults.standard.array(forKey: key) as? [Data] else { return [] }
        return bookmarks.compactMap { bookmark in
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), SecurityScopedAccessManager.shared.retainAccess(to: url) else { return nil }
            return url
        }
    }

    private static func saveBookmarks(_ urls: [URL], forKey key: String) {
        let bookmarks = urls.compactMap { try? $0.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) }
        UserDefaults.standard.set(bookmarks, forKey: key)
    }

    private static func sourceKey(for link: String) -> String? {
        guard let host = URL(string: link)?.host?.lowercased() else { return nil }
        if host.hasSuffix("youtube.com") || host.hasSuffix("youtu.be") { return "youtube" }
        if host.hasSuffix("tiktok.com") { return "tiktok" }
        if host.hasSuffix("instagram.com") || host.hasSuffix("instagr.am") { return "instagram" }
        if host.hasSuffix("facebook.com") || host.hasSuffix("fb.watch") { return "facebook" }
        if host.hasSuffix("drive.google.com") || host.hasSuffix("docs.google.com") { return "drive" }
        return host
    }
}

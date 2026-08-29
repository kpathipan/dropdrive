import Foundation

/// Stable identity for video links. Share URLs commonly gain `utm_*`, `si`,
/// `feature`, or `fbclid` parameters; treating each spelling as a new video made
/// duplicate detection miss the same item and could create another download.
nonisolated enum LinkIdentity {
    static func videoItemID(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let rawHost = components.host?.lowercased() else {
            return "video:\(trimmed)"
        }

        let host = rawHost.removingCommonWebPrefix
        let pathParts = components.path.split(separator: "/").map(String.init)

        if host == "youtu.be", let id = pathParts.first, !id.isEmpty {
            return "video:youtube:\(id)"
        }
        if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            if let id = components.queryItems?.first(where: { $0.name == "v" })?.value, !id.isEmpty {
                return "video:youtube:\(id)"
            }
            if let marker = pathParts.firstIndex(where: { ["shorts", "embed", "live"].contains($0) }),
               pathParts.indices.contains(marker + 1) {
                return "video:youtube:\(pathParts[marker + 1])"
            }
        }

        if host == "tiktok.com" || host.hasSuffix(".tiktok.com"),
           let marker = pathParts.firstIndex(where: { ["video", "photo"].contains($0) }),
           pathParts.indices.contains(marker + 1) {
            return "video:tiktok:\(pathParts[marker + 1])"
        }

        if host == "instagram.com" || host.hasSuffix(".instagram.com"),
           let marker = pathParts.firstIndex(where: { ["p", "reel", "reels", "tv"].contains($0) }),
           pathParts.indices.contains(marker + 1) {
            return "video:instagram:\(pathParts[marker + 1])"
        }

        components.scheme = components.scheme?.lowercased()
        components.host = host
        components.fragment = nil
        components.queryItems = components.queryItems?
            .filter { !Self.isTrackingParameter($0.name) }
            .sorted { lhs, rhs in
                if lhs.name == rhs.name { return (lhs.value ?? "") < (rhs.value ?? "") }
                return lhs.name < rhs.name
            }
        return "video:\(components.url?.absoluteString ?? trimmed)"
    }

    private static func isTrackingParameter(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("utm_") || ["fbclid", "gclid", "si", "feature", "ref", "share_id"].contains(lower)
    }
}

private nonisolated extension String {
    var removingCommonWebPrefix: String {
        for prefix in ["www.", "m.", "mobile."] where hasPrefix(prefix) {
            return String(dropFirst(prefix.count))
        }
        return self
    }
}

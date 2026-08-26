import Foundation

/// Foundation-only link handling for the macOS Share extension. The main app
/// still performs authoritative parsing; this keeps the extension fast while
/// allowing a single share action to hand off several supported links.
nonisolated enum ShareLinkExtractor {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    private static let supportedHosts = [
        "drive.google.com", "docs.google.com", "youtube.com", "youtu.be",
        "tiktok.com", "instagram.com", "instagr.am", "facebook.com", "fb.watch"
    ]

    static func links(from raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var candidates: [String] = []
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        detector?.enumerateMatches(in: trimmed, range: range) { match, _, _ in
            guard let url = match?.url,
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "")
            else { return }
            candidates.append(url.absoluteString)
        }

        if candidates.isEmpty,
           let url = URL(string: trimmed),
           ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            candidates = [trimmed]
        }

        var seen = Set<String>()
        return candidates.filter { link in
            guard isSupported(link) else { return false }
            return seen.insert(normalizedIdentity(for: link)).inserted
        }
    }

    static func deepLink(for links: [String]) -> URL? {
        guard !links.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "dropdrive"
        components.host = "download"
        components.queryItems = links.map { URLQueryItem(name: "url", value: $0) }
        return components.url
    }

    private static func isSupported(_ raw: String) -> Bool {
        guard let components = URLComponents(string: raw),
              let host = components.host?.lowercased() else { return false }
        return supportedHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private static func normalizedIdentity(for raw: String) -> String {
        guard var components = URLComponents(string: raw) else { return raw }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        return components.string ?? raw
    }
}

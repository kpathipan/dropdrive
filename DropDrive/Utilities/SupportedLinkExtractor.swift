import Foundation

/// One lightweight parser shared by paste, clipboard, Services, and menu-bar
/// drag-and-drop. It extracts only links DropDrive understands, preserves the
/// order in which they appeared, and removes duplicate spellings of the same
/// Drive item or video.
nonisolated enum SupportedLinkExtractor {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    private static let videoHosts = [
        "tiktok.com", "youtube.com", "youtu.be", "facebook.com", "fb.watch",
        "instagram.com", "instagr.am"
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

        // NSDataDetector can miss a value while a paste is still being committed.
        // Preserve the old single-link fallback without accepting arbitrary text.
        if candidates.isEmpty,
           let url = URL(string: trimmed),
           ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            candidates = [trimmed]
        }

        var identities: [String: Int] = [:]
        var output: [String] = []
        for link in candidates where isSupported(link) {
            let identity = identity(for: link)
            if let existingIndex = identities[identity] {
                // A resource-key Drive link is strictly more useful than the same
                // URL without one, so retain it when both are present.
                if GoogleDriveLinkParser.resourceKey(from: link) != nil,
                   GoogleDriveLinkParser.resourceKey(from: output[existingIndex]) == nil {
                    output[existingIndex] = link
                }
            } else {
                identities[identity] = output.count
                output.append(link)
            }
        }
        return output
    }

    static func isSupported(_ raw: String) -> Bool {
        GoogleDriveLinkParser.itemID(from: raw) != nil || isPotentialVideoLink(raw)
    }

    static func isPotentialVideoLink(_ raw: String) -> Bool {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased() else { return false }
        return videoHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private static func identity(for link: String) -> String {
        if let driveID = GoogleDriveLinkParser.itemID(from: link) {
            return "drive:\(driveID)"
        }
        return LinkIdentity.videoItemID(for: link)
    }
}

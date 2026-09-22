import Foundation

/// Shared release pages may contain Mac, Windows, or both. Never let a Windows
/// release hide an older (but still newer than installed) Mac update.
nonisolated enum PlatformReleaseCatalog {
    static let automaticInterval: TimeInterval = 24 * 60 * 60

    static func versionParts(_ value: String) -> [Int]? {
        let value = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let fields = value.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3, fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              fields.allSatisfy({ Int($0) != nil }) else { return nil }
        return fields.compactMap { Int($0) }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = versionParts(candidate), let b = versionParts(current) else { return false }
        return b.lexicographicallyPrecedes(a)
    }

    static func latestMac(in releases: [PlatformRelease], current: String) -> PlatformRelease? {
        releases.filter {
            !$0.draft && !$0.prerelease && versionParts($0.tagName) != nil
                && isNewer($0.tagName, than: current) && $0.macAsset != nil
        }.max { isNewer($1.tagName, than: $0.tagName) }
    }
}

nonisolated struct PlatformRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let size: Int64
        let browserDownloadURL: URL
        private enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadURL = "browser_download_url"
        }
    }
    let tagName: String
    let body: String?
    let assets: [Asset]
    let draft: Bool
    let prerelease: Bool
    var macAsset: Asset? {
        assets.first { $0.name == "DropDrive-\(tagName.hasPrefix("v") ? tagName : "v" + tagName).dmg"
            && $0.size > 0 && $0.browserDownloadURL.scheme == "https" }
    }
    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body, assets, draft, prerelease
    }
}

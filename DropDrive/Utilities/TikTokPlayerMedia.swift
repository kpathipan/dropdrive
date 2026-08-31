import Foundation

/// Selects TikTok's original player rendition instead of the branded copy
/// exposed by the public embed page.
enum TikTokPlayerMedia {
    static func watermarkFreeVideoURL(
        from data: Data,
        quality: DriveLinkAnalysis.VideoQuality
    ) -> URL? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = (root["items"] as? [[String: Any]])?.first,
              let videoInfo = item["video_info"] as? [String: Any]
        else { return nil }

        let profiles = videoInfo["profiles"] as? [[String: Any]] ?? []
        let metadata = videoInfo["meta"] as? [String: Any]
        let cap: Int? = quality == .small ? 480 : nil
        let eligible = profiles.filter { profile in
            guard let cap else { return true }
            let address = profile["play_addr"] as? [String: Any]
            let width = number(address?["width"]) ?? number(metadata?["width"])
            let height = number(address?["height"]) ?? number(metadata?["height"])
            guard let width, let height else { return false }
            return min(width, height) <= cap
        }
        let ranked = (eligible.isEmpty ? profiles : eligible).sorted { lhs, rhs in
            let lhsBitrate = number(lhs["bitrate"]) ?? 0
            let rhsBitrate = number(rhs["bitrate"]) ?? 0
            return lhsBitrate > rhsBitrate
        }

        for profile in ranked {
            guard let address = profile["play_addr"] as? [String: Any],
                  let rawURLs = address["url_list"] as? [String]
            else { continue }
            for rawURL in rawURLs {
                if let url = trustedMediaURL(rawURL) { return url }
            }
        }

        let fallbackURLs = videoInfo["url_list"] as? [String] ?? []
        for rawURL in fallbackURLs {
            if let url = trustedMediaURL(rawURL) { return url }
        }
        return nil
    }

    private static func number(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string)
        default: return nil
        }
    }

    private static func trustedMediaURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "tiktokcdn.com" || host.hasSuffix(".tiktokcdn.com")
                || host == "tiktokv.com" || host.hasSuffix(".tiktokv.com")
        else { return nil }
        return url
    }
}

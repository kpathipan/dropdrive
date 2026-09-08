import Foundation

nonisolated enum VideoDownloadPolicy {
    enum Failure: String, Error, Sendable {
        case network, destination, space, authentication, source
    }

    static func platform(for link: String) -> String? {
        guard let host = URL(string: link)?.host?.lowercased() else { return nil }
        for (platform, domains) in [
            ("tiktok", ["tiktok.com"]), ("youtube", ["youtube.com", "youtu.be"]),
            ("instagram", ["instagram.com", "instagr.am"]), ("facebook", ["facebook.com", "fb.watch"])
        ] where domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return platform
        }
        return nil
    }

    static func failure(for message: String) -> Failure {
        let value = message.lowercased()
        if ["no space left", "disk full", "errno 28"].contains(where: value.contains) { return .space }
        if ["network is unreachable", "timed out", "timeout", "connection reset", "connection refused", "temporary failure", "name resolution", "remote end closed", "http error 429", "http error 5"].contains(where: value.contains) { return .network }
        if ["sign in", "login required", "log in", "private video", "cookies", "authentication", "http error 401"].contains(where: value.contains) { return .authentication }
        if ["read-only file system", "permission denied", "no such file or directory", "input/output error", "device not configured"].contains(where: value.contains) { return .destination }
        return .source
    }

    static func rateArguments(_ limit: Double?) -> [String] {
        guard let limit, limit.isFinite, limit > 0 else { return [] }
        return ["--limit-rate", String(Int64(min(limit, Double(Int64.max / 2))))]
    }

    static func savedQuality(for link: String, defaults: UserDefaults = .standard) -> DriveLinkAnalysis.VideoQuality {
        guard let platform = platform(for: link),
              let raw = defaults.string(forKey: "videoChoice." + platform),
              let value = DriveLinkAnalysis.VideoQuality(rawValue: raw) else { return .automatic }
        return value
    }

    static func saveQuality(_ value: DriveLinkAnalysis.VideoQuality, for link: String, defaults: UserDefaults = .standard) {
        guard let platform = platform(for: link) else { return }
        defaults.set(value.rawValue, forKey: "videoChoice." + platform)
        if value != .mp3 { defaults.set(value.rawValue, forKey: "videoQuality." + platform) }
    }

    static func savedVideoQuality(for link: String, defaults: UserDefaults = .standard) -> DriveLinkAnalysis.VideoQuality {
        guard let platform = platform(for: link) else { return .automatic }
        let raw = defaults.string(forKey: "videoQuality." + platform)
        let stored = raw.flatMap(DriveLinkAnalysis.VideoQuality.init(rawValue:)) ?? savedQuality(for: link, defaults: defaults)
        return stored == .mp3 ? .automatic : stored
    }
}

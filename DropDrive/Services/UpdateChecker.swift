import Foundation
import UserNotifications

/// Compares the running app's version against the latest GitHub Release and, if a
/// newer semantic version exists, shows a local notification linking to the release
/// page. Never downloads or installs anything itself.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    // Set this once a public repository exists, e.g. (owner: "yourorg", name: "dropdrive").
    // The checker is a no-op while this is nil.
    private static let repository: (owner: String, name: String)? = nil

    private static let lastCheckKey = "updateChecker.lastCheckDate"
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    static let updateAvailableCategoryID = "UPDATE_AVAILABLE"
    static let releaseURLKey = "releaseURL"

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func checkIfNeeded() {
        guard let repository = Self.repository else { return }

        let lastCheck = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.checkInterval {
            return
        }

        Task {
            await performCheck(repository: repository)
        }
    }

    private func performCheck(repository: (owner: String, name: String)) async {
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

        guard let url = URL(string: "https://api.github.com/repos/\(repository.owner)/\(repository.name)/releases/latest") else {
            return
        }

        do {
            let (data, response) = try await urlSession.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  Self.isNewer(release.tagName, than: currentVersion) else {
                return
            }

            notifyUpdateAvailable(version: release.tagName, releaseURL: release.htmlURL)
        } catch {
            // Silent failure: this is a best-effort, optional check.
        }
    }

    private func notifyUpdateAvailable(version: String, releaseURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = "DropDrive Update Available"
        content.body = "\(version) is available on GitHub."
        content.categoryIdentifier = Self.updateAvailableCategoryID
        content.userInfo = [Self.releaseURLKey: releaseURL.absoluteString]

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Compares two "vX.Y.Z"-style (leading "v" optional) semantic version strings.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidateComponents = versionComponents(candidate),
              let currentComponents = versionComponents(current) else {
            return false
        }

        for (candidatePart, currentPart) in zip(candidateComponents, currentComponents) {
            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }
        return candidateComponents.count > currentComponents.count
    }

    private static func versionComponents(_ version: String) -> [Int]? {
        let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let stringParts = trimmed.split(separator: ".")
        let intParts = stringParts.compactMap { Int($0) }
        guard !intParts.isEmpty, intParts.count == stringParts.count else { return nil }
        return intParts
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

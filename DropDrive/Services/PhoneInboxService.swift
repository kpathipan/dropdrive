import Foundation
import Observation

/// "Send from phone": an iOS Shortcut saves shared links as small text files
/// into `iCloud Drive/DropDrive/`; this service watches that folder on the Mac,
/// queues every link it finds, and deletes the file. Polling (not FSEvents)
/// because iCloud delivers files with odd timing and placeholder states — a
/// cheap 8-second directory scan is far more dependable.
@MainActor
@Observable
final class PhoneInboxService {
    static let shared = PhoneInboxService()

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.defaultsKey)
            isEnabled ? start() : stop()
        }
    }

    /// Visible in Finder as "DropDrive" at the top level of iCloud Drive.
    nonisolated static let inboxURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/DropDrive", isDirectory: true)

    private static let defaultsKey = "phoneInboxEnabled"
    private var timer: Timer?

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true
        if isEnabled { start() }
    }

    private func start() {
        try? FileManager.default.createDirectory(at: Self.inboxURL, withIntermediateDirectories: true)
        timer?.invalidate()
        let timer = Timer(timeInterval: 8, repeats: true) { _ in
            Task { @MainActor in PhoneInboxService.shared.scan() }
        }
        // Nothing here is time-critical, and this runs for the app's whole
        // lifetime — let the OS fold the wake-up into one it was making anyway.
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        scan()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// The listing happens off the main actor: this is an iCloud folder, so the
    /// read can block on the network, and it was blocking the UI every 8
    /// seconds whether or not anything was ever in there.
    private func scan() {
        Task {
            let contents = await Self.inboxContents()
            guard !contents.isEmpty else { return }
            consume(contents)
        }
    }

    private static func inboxContents() async -> [URL] {
        await Task.detached(priority: .utility) {
            (try? FileManager.default.contentsOfDirectory(
                at: inboxURL, includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
            )) ?? []
        }.value
    }

    private func consume(_ contents: [URL]) {
        for file in contents {
            let ext = file.pathExtension.lowercased()

            // iCloud placeholder that hasn't downloaded to this Mac yet — ask
            // for it and pick it up on a later scan.
            if ext == "icloud" {
                try? FileManager.default.startDownloadingUbiquitousItem(at: file)
                continue
            }

            guard ["txt", "url", "webloc"].contains(ext) else { continue }
            guard let raw = try? String(contentsOf: file, encoding: .utf8) else { continue }

            let links = Self.extractLinks(from: raw)
            // Consume the file first so a crash mid-queue can't loop forever.
            try? FileManager.default.removeItem(at: file)
            guard !links.isEmpty else { continue }
            DropDriveViewModel.shared.receiveExternalLinks(links, sourceLabel: tr("from your phone", "จากมือถือ"))
        }
    }

    /// Pulls http(s) URLs out of plain text, .url (INI), or .webloc (plist) content.
    private static func extractLinks(from raw: String) -> [String] {
        var links: [String] = []
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(raw.startIndex..., in: raw)
        detector?.enumerateMatches(in: raw, range: range) { match, _, _ in
            if let url = match?.url, url.scheme == "https" || url.scheme == "http" {
                links.append(url.absoluteString)
            }
        }
        return links
    }
}

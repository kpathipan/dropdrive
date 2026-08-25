import Foundation
import Observation

/// "Send from phone": an iOS Shortcut saves shared links as small text files
/// into `iCloud Drive/DropDrive/`; this service watches that folder on the Mac,
/// queues every link it finds, and consumes the file only after a durable
/// queue/duplicate result. Polling (not FSEvents)
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
    private var isScanning = false
    private var retryAttempts: [String: Int] = [:]
    private var retryAfter: [String: Date] = [:]

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
        guard !isScanning else { return }
        isScanning = true
        Task {
            let contents = await Self.inboxContents()
            await consume(contents)
            isScanning = false
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

    private func consume(_ contents: [URL]) async {
        for file in contents {
            let retryKey = file.standardizedFileURL.path
            if let date = retryAfter[retryKey], date > .now { continue }
            let ext = file.pathExtension.lowercased()

            // iCloud placeholder that hasn't downloaded to this Mac yet — ask
            // for it and pick it up on a later scan.
            if ext == "icloud" {
                try? FileManager.default.startDownloadingUbiquitousItem(at: file)
                continue
            }

            guard ["txt", "url", "webloc"].contains(ext) else { continue }
            guard let raw = try? String(contentsOf: file, encoding: .utf8) else {
                scheduleRetry(for: retryKey)
                continue
            }

            let links = Self.extractLinks(from: raw)
            guard !links.isEmpty else {
                archiveRejected(file)
                clearRetry(for: retryKey)
                continue
            }

            let receipt = await DropDriveViewModel.shared.receiveExternalLinks(
                links,
                sourceLabel: tr("from your phone", "จากมือถือ"),
                notify: retryAttempts[retryKey] == nil
            )
            switch receipt.disposition {
            case .consume:
                try? FileManager.default.removeItem(at: file)
                clearRetry(for: retryKey)
            case .retry:
                // Keep the original iCloud file. A later scan retries it; any
                // links already queued in a mixed file are then duplicates.
                scheduleRetry(for: retryKey)
            case .archiveRejected:
                archiveRejected(file)
                clearRetry(for: retryKey)
            }
        }
    }

    private func scheduleRetry(for key: String) {
        let attempt = min((retryAttempts[key] ?? 0) + 1, 8)
        retryAttempts[key] = attempt
        let delay = min(15 * 60.0, 15.0 * pow(2.0, Double(attempt - 1)))
        retryAfter[key] = .now.addingTimeInterval(delay)
    }

    private func clearRetry(for key: String) {
        retryAttempts.removeValue(forKey: key)
        retryAfter.removeValue(forKey: key)
    }

    private func archiveRejected(_ file: URL) {
        let rejected = Self.inboxURL.appendingPathComponent("Rejected", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: rejected, withIntermediateDirectories: true)
            let destination = UniqueDestinationNaming.uniqueURL(
                for: rejected.appendingPathComponent(file.lastPathComponent)
            )
            try FileManager.default.moveItem(at: file, to: destination)
        } catch {
            // Keeping the original in place is safer than deleting an input we
            // could not archive. It can be recovered or retried manually.
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

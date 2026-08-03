import AppKit
import CryptoKit
import Foundation
import Observation
import UserNotifications

/// Checks GitHub Releases for a newer build and, on request, installs it.
///
/// Sparkle was ruled out when the app was ad-hoc signed — its own documentation
/// says an ad-hoc signature keeps the hardened runtime from loading it — and
/// this small replacement has done the job since: fetch the latest release,
/// compare versions, download the DMG, verify it against the SHA-256 published
/// in the release notes, and swap the app bundle in place. Builds are signed
/// with a certificate now (see `build-dmg.sh`), so Sparkle would work, but
/// there's no reason left to want it.
///
/// Replacing our own bundle is allowed even with App Management protection
/// active — verified on macOS 26.5.2 with SIP on: the app is blocked from
/// writing into a *different* Developer-ID-signed app in /Applications
/// (NSCocoaErrorDomain 513) but permitted to replace itself.
@MainActor
@Observable
final class UpdateService {
    static let shared = UpdateService()

    /// The GitHub repository releases are published to, as "owner/name".
    /// Empty disables update checking entirely (the state before a repo exists).
    /// This is the one line to fill in.
    nonisolated static let repository = "kpathipan/dropdrive"

    struct Release: Equatable, Sendable {
        let version: String
        /// The first few lines, for the collapsed card.
        let notes: String
        /// Everything the release says, for the expanded "what's new" view.
        let fullNotes: String
        let downloadURL: URL
        let sizeBytes: Int64
        /// From a "sha256: <hex>" line in the release notes. Optional, because a
        /// release published by hand through GitHub's web UI won't have one.
        let sha256: String?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(fraction: Double)
        case installing
        case failed(String)
    }

    private(set) var state: State = .idle

    /// The release last offered, kept across a failure so the user can try
    /// again without hunting for the "check for updates" button. Every failure
    /// path replaces `.available` with `.failed`, which would otherwise take the
    /// Update button away permanently — including for the entirely recoverable
    /// "finish your download first" case.
    private(set) var offeredRelease: Release?

    /// True once a release has been offered this session. Lets the main-screen
    /// banner show install failures while staying silent about a background
    /// check that simply couldn't reach the network.
    var hasOfferedUpdate: Bool { offeredRelease != nil }

    private var periodicTimer: Timer?

    private static let lastCheckKey = "updateChecker.lastCheckDate"
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    static let updateAvailableCategoryID = "UPDATE_AVAILABLE"
    static let installActionID = "INSTALL_UPDATE"
    static let releaseURLKey = "releaseURL"

    var isConfigured: Bool { !Self.repository.isEmpty }

    /// True while a download or install is in flight, so the UI can't start a second.
    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    // MARK: - Checking

    /// Keeps the daily check happening on a Mac that never restarts.
    ///
    /// `checkIfNeeded()` was only ever called from the app's initialiser, which
    /// reads as "once a day" but is really "once per launch" — and this is a
    /// menu bar agent that launches at login and then stays up. Someone who
    /// leaves their Mac running for a fortnight got exactly one check, so a
    /// release could sit unannounced until they happened to reboot.
    ///
    /// Waking from sleep is included because a laptop closed overnight crosses
    /// the daily boundary while the timer is suspended.
    func startPeriodicChecks() {
        guard isConfigured, periodicTimer == nil else { return }

        let timer = Timer(timeInterval: 2 * 60 * 60, repeats: true) { _ in
            Task { @MainActor in UpdateService.shared.checkIfNeeded() }
        }
        // The 24-hour minimum inside checkIfNeeded() is what actually paces
        // this, so the timer only has to land somewhere near the boundary —
        // no reason to make the machine wake up for it.
        timer.tolerance = 30 * 60
        RunLoop.main.add(timer, forMode: .common)
        periodicTimer = timer

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { UpdateService.shared.checkIfNeeded() }
        }
    }

    /// Silent, once a day, at launch.
    func checkIfNeeded() {
        guard isConfigured else { return }
        let lastCheck = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.checkInterval { return }
        Task { await check(notifying: true) }
    }

    /// Puts a previously-offered release back on the table after a failure the
    /// user has since fixed — pausing the queue, reconnecting, and so on.
    func retryOffer() {
        guard let offeredRelease, !isBusy else { return }
        state = .available(offeredRelease)
    }

    /// The notification's "Update now" button.
    ///
    /// Tapping it can relaunch the app, in which case no check has run and
    /// there is no release in hand — `installUpdate()` alone would find state
    /// `.idle`, return silently, and leave the user pressing a button that does
    /// nothing. Fetch first when that's the case.
    func installFromNotification() {
        if case .available = state {
            installUpdate()
            return
        }
        guard isConfigured, !isBusy else { return }
        Task {
            await check(notifying: false)
            if case .available = state { installUpdate() }
        }
    }

    /// Explicit "Check for updates" from Preferences.
    func checkNow() {
        guard isConfigured, !isBusy else { return }
        Task { await check(notifying: false) }
    }

    private func check(notifying: Bool) async {
        state = .checking

        do {
            guard let release = try await Self.fetchLatestRelease() else {
                UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                state = .upToDate
                return
            }
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            offeredRelease = release
            state = .available(release)
            if notifying { Self.notify(release) }
        } catch {
            state = .failed(tr(
                "Couldn't check for updates. Check your internet connection.",
                "เช็คอัปเดตไม่ได้ ตรวจสอบการเชื่อมต่ออินเทอร์เน็ต"
            ))
        }
    }

    /// nil when the newest release isn't newer than what's running.
    private nonisolated static func fetchLatestRelease() async throws -> Release? {
        let endpoint = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.badResponse
        }

        let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              isNewer(payload.tagName, than: current) else {
            return nil
        }
        // A release with no .dmg attached isn't installable — treat it as nothing
        // to offer rather than as an error.
        guard let asset = payload.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            return nil
        }

        let body = payload.body ?? ""
        return Release(
            version: payload.tagName.hasPrefix("v") ? String(payload.tagName.dropFirst()) : payload.tagName,
            notes: Self.summarize(body),
            fullNotes: Self.readable(body),
            downloadURL: asset.browserDownloadURL,
            sizeBytes: asset.size,
            sha256: Self.sha256(fromNotes: body)
        )
    }

    /// Pulls "sha256: <hex>" out of the release notes, case-insensitively.
    private nonisolated static func sha256(fromNotes notes: String) -> String? {
        for rawLine in notes.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces).lowercased()
            guard line.hasPrefix("sha256:") else { continue }
            let value = line.dropFirst("sha256:".count).trimmingCharacters(in: .whitespaces)
            let hex = value.filter(\.isHexDigit)
            if hex.count == 64 { return hex }
        }
        return nil
    }

    /// The first few meaningful lines of the release notes, for the update card.
    private nonisolated static func summarize(_ body: String) -> String {
        let headings = Set(
            body.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("#") }
                .map { $0.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) + ":" }
        )
        return readable(body)
            .split(separator: "\n")
            // Section headings only — `readable` is what turns "### Fixed"
            // into "Fixed:", so anything else ending in a colon is real prose.
            .filter { !headings.contains(String($0)) }
            .prefix(3)
            .joined(separator: "\n")
    }

    /// The release notes with their Markdown flattened — the notes come from a
    /// CHANGELOG section, and raw `###` and `**` read as noise in a popover that
    /// doesn't render Markdown.
    private nonisolated static func readable(_ body: String) -> String {
        var lines: [String] = []
        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("sha256:") { continue }
            // "### Fixed" becomes "Fixed:", which reads as a heading without one.
            if line.hasPrefix("#") {
                line = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                lines.append("\(line):")
                continue
            }
            line = line.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
            if line.hasPrefix("- ") { line = "•  " + line.dropFirst(2) }
            // Collapse runs of blank lines rather than dropping them entirely;
            // the spacing is what separates one section from the next.
            if line.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(line)
        }
        while lines.last?.isEmpty ?? false { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    // MARK: - Installing

    /// Downloads, verifies, and swaps in the new build, then relaunches.
    ///
    /// Refuses while the queue is busy: replacing the running app mid-download
    /// would kill the transfer and strand its partial files.
    func installUpdate() {
        guard case .available(let release) = state else { return }

        if DropDriveViewModel.shared.isQueueProcessing {
            state = .failed(tr(
                "Finish or pause the current download first, then update.",
                "รอให้ดาวน์โหลดที่ค้างอยู่เสร็จ หรือกดหยุดก่อน แล้วค่อยอัปเดต"
            ))
            return
        }

        let installedAt = Bundle.main.bundleURL
        guard installedAt.path.hasPrefix("/Applications/") else {
            state = .failed(tr(
                "DropDrive can only update itself from the Applications folder. Move it there first.",
                "แอพอัปเดตตัวเองได้เฉพาะตอนอยู่ในโฟลเดอร์ Applications ย้ายไปไว้ที่นั่นก่อน"
            ))
            return
        }

        state = .downloading(fraction: 0)
        Task {
            do {
                let dmg = try await Self.download(release) { fraction in
                    Task { @MainActor in
                        if case .downloading = self.state { self.state = .downloading(fraction: fraction) }
                    }
                }
                state = .installing
                let staged = try await Self.stageApp(fromDMG: dmg, expecting: release.sha256)
                // Re-checked here rather than only up front: the download takes
                // long enough for the user to have started something in the
                // meantime, and the swap is the moment that would kill it.
                guard !DropDriveViewModel.shared.isQueueProcessing else {
                    try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
                    throw UpdateError.queueBusy
                }
                try await Self.swapInPlace(staged: staged, installedAt: installedAt)
                Self.relaunchAndQuit(installedAt: installedAt)
            } catch let error as UpdateError {
                state = .failed(error.message)
            } catch {
                state = .failed(tr("The update couldn't be installed.", "ติดตั้งอัปเดตไม่สำเร็จ"))
            }
        }
    }

    private nonisolated static func download(
        _ release: Release,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let coordinator = DownloadProgressCoordinator(total: release.sizeBytes, onProgress: onProgress)
        let session = URLSession(configuration: .ephemeral, delegate: coordinator, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await coordinator.run(session: session, url: release.downloadURL)
    }

    /// Mounts the DMG, copies the app out, and clears the quarantine flag the
    /// download attached — without that last step Gatekeeper refuses to launch
    /// an ad-hoc signed app, which is exactly what a manual install works around
    /// by right-click-Open.
    private nonisolated static func stageApp(fromDMG dmg: URL, expecting sha256: String?) async throws -> URL {
        defer { try? FileManager.default.removeItem(at: dmg) }

        if let expected = sha256 {
            let actual = try Self.digest(of: dmg)
            guard actual == expected else { throw UpdateError.checksumMismatch }
        }

        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropDrive-update-\(UUID().uuidString)", isDirectory: true)
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-quiet", "-mountpoint", mountPoint.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"]) }

        let contents = (try? FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)) ?? []
        guard let source = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.noAppInDMG
        }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropDrive-staged-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: staged)

        _ = try? run("/usr/bin/xattr", ["-cr", staged.path])
        // A truncated or tampered download can still be a mountable DMG; make
        // sure what came out of it is an intact, signed bundle before it
        // replaces a working app.
        try run("/usr/bin/codesign", ["--verify", "--deep", staged.path])
        try requireSameSigner(as: Bundle.main.bundleURL, staged: staged)
        try requireRunnableArchitecture(staged: staged)
        try requireSupportedOSVersion(staged: staged)
        return staged
    }

    /// Refuses an update signed by anyone other than whoever signed the running
    /// copy.
    ///
    /// The checksum check above only bites when the release notes carry a
    /// `sha256:` line; a release published by hand, or one whose notes were
    /// edited, has no integrity check at all — and the app would then install
    /// whatever DMG happened to be attached. Comparing team identifiers doesn't
    /// depend on the notes saying anything. Skipped when the running copy has no
    /// team of its own (an ad-hoc local build), since there's nothing to match.
    private nonisolated static func requireSameSigner(as installed: URL, staged: URL) throws {
        guard let mine = teamIdentifier(of: installed), !mine.isEmpty else { return }
        guard teamIdentifier(of: staged) == mine else {
            throw UpdateError.wrongSigner
        }
    }

    /// Refuses an update this Mac can't actually execute.
    ///
    /// Builds are Apple Silicon only from 6.13.0 on. Nothing else in the
    /// install path would notice: the checksum matches, the signature verifies,
    /// the team is right, so an Intel Mac would replace a working app with one
    /// that cannot launch — and the relaunch helper deletes the old copy on the
    /// way out, leaving nothing to fall back to and no way to recover from
    /// inside the app. Cheap insurance against ever shipping a build that
    /// strands someone.
    private nonisolated static func requireRunnableArchitecture(staged: URL) throws {
        let executable = staged
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(staged.deletingPathExtension().lastPathComponent)
        guard let archs = try? run("/usr/bin/lipo", ["-archs", executable.path]) else { return }

        #if arch(arm64)
        let required = "arm64"
        #elseif arch(x86_64)
        let required = "x86_64"
        #else
        return
        #endif

        guard archs.split(separator: " ").contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == required }) else {
            throw UpdateError.unsupportedArchitecture
        }
    }

    /// Refuses an update that declares a higher minimum macOS than this Mac
    /// runs. Same failure as the architecture case — it would install cleanly
    /// and then refuse to launch — and it becomes reachable the moment the
    /// deployment target is ever raised.
    private nonisolated static func requireSupportedOSVersion(staged: URL) throws {
        let plistURL = staged.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let minimum = plist["LSMinimumSystemVersion"] as? String else { return }

        let required = minimum.split(separator: ".").compactMap { Int($0) }
        guard !required.isEmpty else { return }
        let current = ProcessInfo.processInfo.operatingSystemVersion
        let running = [current.majorVersion, current.minorVersion, current.patchVersion]

        for (needed, have) in zip(required, running) where needed != have {
            if needed > have { throw UpdateError.unsupportedOSVersion(minimum) }
            return
        }
    }

    private nonisolated static func teamIdentifier(of bundle: URL) -> String? {
        guard let output = try? run("/usr/bin/codesign", ["-dvvv", bundle.path]) else { return nil }
        for line in output.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
            let value = line.dropFirst("TeamIdentifier=".count).trimmingCharacters(in: .whitespaces)
            return value == "not set" ? nil : value
        }
        return nil
    }

    /// Moves the current bundle aside and puts the new one in its place. The old
    /// copy can't be deleted from inside the running process — the relaunch
    /// helper does that once we've exited.
    ///
    /// `async` so it runs off the main actor: this was a synchronous call from a
    /// MainActor task, which pinned a full bundle copy to the main thread and
    /// froze the window for it. Moving rather than copying does most of the
    /// work — staging lives in the temp directory, which is the same volume as
    /// /Applications, so the move is a rename. Measured on a 201 MB bundle: 92 ms
    /// to copy, 0.1 ms to rename. The copy stays as the fallback for the case
    /// where the two really are on different volumes.
    private nonisolated static func swapInPlace(staged: URL, installedAt: URL) async throws {
        let retired = installedAt.appendingPathExtension("old")
        try? FileManager.default.removeItem(at: retired)
        try FileManager.default.moveItem(at: installedAt, to: retired)
        do {
            do {
                try FileManager.default.moveItem(at: staged, to: installedAt)
            } catch {
                try FileManager.default.copyItem(at: staged, to: installedAt)
            }
        } catch {
            // Put the working app back rather than leaving nothing installed.
            try? FileManager.default.moveItem(at: retired, to: installedAt)
            throw UpdateError.swapFailed
        }
        try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
    }

    /// Hands off to a detached shell that waits for this process to exit, clears
    /// the retired bundle, and opens the new one.
    private nonisolated static func relaunchAndQuit(installedAt: URL) {
        // Paths arrive as arguments, not spliced into the script text: this
        // script runs `rm -rf`, and a bundle the user had renamed to something
        // containing a quote would otherwise change what that line means.
        //
        // The retired bundle is kept until the new version proves it can run.
        // Every check before this point tests a specific, anticipated failure —
        // a bad checksum, a wrong signer, an architecture this Mac can't
        // execute — and none of them would catch a build that is perfectly
        // valid and simply crashes on launch. That failure is the one that
        // matters most: every friend's copy updates to it, every copy dies, and
        // the fix can only reach them through the app that no longer starts.
        // So the old version is restored automatically if the new one doesn't
        // come up and stay up.
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        open "$3" 2>/dev/null
        ALIVE=0
        for _ in $(seq 1 20); do
          sleep 0.5
          if pgrep -f "$3/Contents/MacOS/" >/dev/null 2>&1; then ALIVE=1; break; fi
        done
        if [ "$ALIVE" = 1 ]; then
          sleep 3
          pgrep -f "$3/Contents/MacOS/" >/dev/null 2>&1 || ALIVE=0
        fi
        if [ "$ALIVE" = 1 ]; then
          rm -rf "$2"
        else
          rm -rf "$3"
          mv "$2" "$3"
          open "$3"
        fi
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", script, "dropdrive-relaunch",
            "\(getpid())", installedAt.path + ".old", installedAt.path
        ]
        try? process.run()

        Task { @MainActor in
            NSApp.terminate(nil)
        }
    }

    private nonisolated static func digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private nonisolated static func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.commandFailed(String(data: data, encoding: .utf8) ?? "")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Notification

    private static func notify(_ release: Release) {
        let content = UNMutableNotificationContent()
        content.title = tr("DropDrive \(release.version) is available", "DropDrive \(release.version) พร้อมอัปเดต")
        content.body = tr("Open DropDrive to install it.", "เปิด DropDrive เพื่อติดตั้ง")
        content.categoryIdentifier = updateAvailableCategoryID
        content.userInfo = [releaseURLKey: release.downloadURL.absoluteString]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    // MARK: - Version comparison

    /// Compares two "vX.Y.Z"-style (leading "v" optional) semantic versions.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidateParts = versionComponents(candidate),
              let currentParts = versionComponents(current) else { return false }
        for (a, b) in zip(candidateParts, currentParts) where a != b {
            return a > b
        }
        return candidateParts.count > currentParts.count
    }

    private nonisolated static func versionComponents(_ version: String) -> [Int]? {
        let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let stringParts = trimmed.split(separator: ".")
        let intParts = stringParts.compactMap { Int($0) }
        guard !intParts.isEmpty, intParts.count == stringParts.count else { return nil }
        return intParts
    }
}

@MainActor
enum UpdateError: Error {
    case badResponse
    case checksumMismatch
    case wrongSigner
    case queueBusy
    case unsupportedArchitecture
    case unsupportedOSVersion(String)
    case noAppInDMG
    case swapFailed
    case commandFailed(String)

    var message: String {
        switch self {
        case .unsupportedOSVersion(let minimum):
            tr(
                "This update needs macOS \(minimum) or later, so it wasn't installed. The version you have keeps working.",
                "อัปเดตนี้ต้องใช้ macOS \(minimum) ขึ้นไป จึงไม่ได้ติดตั้ง เวอร์ชันที่ใช้อยู่ยังใช้งานได้ตามปกติ"
            )
        case .unsupportedArchitecture:
            tr(
                "This update doesn't support this Mac, so it wasn't installed. The version you have keeps working.",
                "อัปเดตนี้ไม่รองรับ Mac เครื่องนี้ จึงไม่ได้ติดตั้ง เวอร์ชันที่ใช้อยู่ยังใช้งานได้ตามปกติ"
            )
        case .queueBusy:
            tr(
                "A download started while the update was being fetched. Pause it, then try again.",
                "มีดาวน์โหลดเริ่มขึ้นระหว่างโหลดอัปเดต กดหยุดก่อนแล้วลองใหม่"
            )
        case .wrongSigner:
            tr(
                "That update wasn't signed by the same developer, so it wasn't installed.",
                "อัปเดตนี้ไม่ได้เซ็นโดยผู้พัฒนาคนเดิม จึงไม่ได้ติดตั้ง"
            )
        case .checksumMismatch:
            tr(
                "The downloaded file didn't match its checksum, so it wasn't installed.",
                "ไฟล์ที่โหลดมาไม่ตรงกับค่าตรวจสอบ จึงไม่ได้ติดตั้ง"
            )
        case .noAppInDMG, .badResponse:
            tr("That update looks incomplete, so it wasn't installed.", "ไฟล์อัปเดตไม่สมบูรณ์ จึงไม่ได้ติดตั้ง")
        case .swapFailed:
            tr(
                "Couldn't replace the installed app. The current version is untouched.",
                "แทนที่แอพเดิมไม่ได้ เวอร์ชันที่ใช้อยู่ยังอยู่ครบ"
            )
        case .commandFailed:
            tr("The update couldn't be installed.", "ติดตั้งอัปเดตไม่สำเร็จ")
        }
    }
}

// MARK: - GitHub payload

private nonisolated struct GitHubRelease: Decodable, Sendable {
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

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body, assets
    }
}

// MARK: - Download plumbing

/// Reports download progress and hands back the finished file. The system
/// deletes the temp file the moment the delegate callback returns, so it's moved
/// somewhere durable inside that callback.
private final class DownloadProgressCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let total: Int64
    private let onProgress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var didResume = false

    init(total: Int64, onProgress: @escaping @Sendable (Double) -> Void) {
        self.total = total
        self.onProgress = onProgress
    }

    func run(session: URLSession, url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            session.downloadTask(with: url).resume()
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        switch result {
        case .success(let url): continuation?.resume(returning: url)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : total
        guard expected > 0 else { return }
        onProgress(min(1, Double(totalBytesWritten) / Double(expected)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let http = downloadTask.response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            finish(.failure(UpdateError.badResponse))
            return
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropDrive-update-\(UUID().uuidString).dmg")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}

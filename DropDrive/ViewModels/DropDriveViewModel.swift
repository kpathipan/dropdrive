import AppKit
import Foundation
import Observation

struct QueueSummary {
    let linkCount: Int
    let totalFiles: Int
    let totalBytes: Int64
    let estimatedSeconds: Double?
}

/// The local destination check shown before an item reaches the queue. The
/// exact same reserve is enforced again at start time, so this is informative
/// without becoming a second source of truth.
struct DestinationPreflight: Equatable {
    let capacity: DestinationCapacity.State
    let requiredBytes: Int64?
    let hasNameCollision: Bool
    let canQueue: Bool

    var spaceDescription: String {
        switch capacity {
        case .notSelected:
            return tr("Choose a folder to check available space.", "เลือกโฟลเดอร์เพื่อตรวจพื้นที่ว่าง")
        case .unavailable:
            return tr("Destination unavailable — choose another folder.", "โฟลเดอร์ปลายทางใช้งานไม่ได้ — เลือกโฟลเดอร์ใหม่")
        case .unknown:
            if let requiredBytes {
                return tr(
                    "Needs \(Formatters.byteCount(requiredBytes)) · free space will be checked while downloading",
                    "ต้องใช้ \(Formatters.byteCount(requiredBytes)) · จะตรวจพื้นที่อีกครั้งระหว่างดาวน์โหลด"
                )
            }
            return tr("Free space will be checked while downloading.", "จะตรวจพื้นที่อีกครั้งระหว่างดาวน์โหลด")
        case .available(let availableBytes):
            if let requiredBytes {
                return tr(
                    "Needs \(Formatters.byteCount(requiredBytes)) · \(Formatters.byteCount(availableBytes)) free",
                    "ต้องใช้ \(Formatters.byteCount(requiredBytes)) · เหลือ \(Formatters.byteCount(availableBytes))"
                )
            }
            return tr("Size unknown · \(Formatters.byteCount(availableBytes)) free", "ยังไม่ทราบขนาด · เหลือ \(Formatters.byteCount(availableBytes))")
        }
    }
}

@MainActor
@Observable
final class DropDriveViewModel {
    /// The menu-bar UI, Services, Share extension, and deep links all feed the
    /// same live queue/progress state rather than independent download engines.
    static let shared = DropDriveViewModel()

    private static let assumedDownloadRateBytesPerSecond: Double = 5_000_000 // conservative ~5 MB/s estimate for the ETA shown before starting
    private static let batchAnalysisConcurrency = 4

    private nonisolated enum BatchWorkResult: Sendable {
        case ready(DriveLinkAnalysis)
        case needsConnection
        case unsupported
        case videoUnavailable
        case failed(FriendlyFailure)
    }

    private nonisolated enum FriendlyFailure: Sendable {
        case outOfSpace
        case driveServer(Int)
        case driveInvalidResponse
        case driveUnsupported
        case integrity
        case offline
        case timedOut
        case network
        case write
        case other
    }

    private nonisolated struct BatchWork: Sendable {
        let link: String
        let result: BatchWorkResult
    }

    var driveLink = "" {
        didSet {
            guard driveLink != oldValue else { return }
            scheduleAnalysis()
        }
    }
    var selectedDestinationURL: URL?
    var googleAccount: GoogleAccount?
    var isSigningIn = false
    var pendingDownloadLink: String?  // Store link when auth needed, retry after login

    var linkAnalysisState: LinkAnalysisState = .idle

    var queue: [QueueItem] = []
    var activeQueueItemID: UUID?
    var activeProgress: DownloadProgress?
    var highlightedQueueItemID: UUID?
    var isQueuePaused = false

    var pendingRestoreQueue: [QueueItem]?
    private var hasAskedAboutRestore = false

    private let loginManager: LoginManaging
    private let downloadService: DownloadServicing
    private let videoDownloadService = VideoDownloadService()
    private let folderSelectionService: FolderSelectionServicing
    private var downloadTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    /// The background yt-dlp pass that fills in a video card's duration and
    /// size. Held so cancelling an analysis cancels this too — it runs for
    /// ~12 seconds after the card appears, long enough for the user to have
    /// moved on, and it was previously fire-and-forget.
    private var enrichmentTask: Task<Void, Never>?
    /// True while the folder panel is up. The enrichment finishing mid-panel
    /// would rebuild the card underneath it.
    private var isChoosingDestination = false
    private var highlightTask: Task<Void, Never>?
    private var isPausingActiveItem = false
    /// Prevents the same clipboard contents from being re-imported every time
    /// the popover is reopened after the user has handled or cleared them.
    private var lastImportedClipboardChangeCount = -1

    /// Auto-retry on network drops: attempts already made per queue item, and the
    /// backoff before each retry. Cleared on success, pause, cancel, or removal.
    private var autoRetryAttempts: [UUID: Int] = [:]
    /// Suppresses one banner per retry attempt. A row may back off five times,
    /// but the user only needs one notification until it genuinely recovers or
    /// they explicitly retry it.
    private var notifiedAttentionItemIDs: Set<UUID> = []
    private static let autoRetryDelays: [Double] = [5, 15, 45, 120, 300]
    @ObservationIgnored private var recoveryObserverTokens: [NSObjectProtocol] = []

    /// Set for 2 seconds after the queue finishes its last item, so the menu bar
    /// icon can flash a checkmark.
    var showCompletionFlash = false
    private var completionFlashTask: Task<Void, Never>?
    /// Capacity lookups can block on a sleeping NAS. SwiftUI may rebuild the
    /// review card several times for an unrelated state change, so keep the
    /// last answer briefly; the start-download gate always performs a fresh
    /// check before writing.
    @ObservationIgnored private var capacityCache: (path: String, state: DestinationCapacity.State, checkedAt: Date)?

    init() {
        let loginManager = LoginManager.shared
        self.loginManager = loginManager
        self.downloadService = GoogleDriveDownloadService(loginManager: loginManager)
        self.folderSelectionService = FolderSelectionService()
        self.selectedDestinationURL = DestinationStore.restore() ?? PreferencesStore.shared.defaultDownloadFolderURL
        checkForSavedQueue()
        installRecoveryObservers()
    }

    init(
        loginManager: LoginManaging,
        downloadService: DownloadServicing,
        folderSelectionService: FolderSelectionServicing
    ) {
        self.loginManager = loginManager
        self.downloadService = downloadService
        self.folderSelectionService = folderSelectionService
    }

    var isQueueProcessing: Bool { activeQueueItemID != nil }

    /// The confirm card can speak in the action the user will actually see.
    /// Completed/failed history rows do not make a queue; ready, paused,
    /// waiting, or active work does.
    var confirmationStartsImmediately: Bool {
        guard !isQueueProcessing, !isQueuePaused else { return false }
        return !queue.contains { item in
            item.status == .ready || item.status == .downloading
                || item.status == .paused || item.status == .waiting
        }
    }

    /// One pass over the queue instead of an intermediate array plus two
    /// reductions. Every one of the properties below used to build its own copy
    /// of `readyItems`, and the whole set is re-read on each SwiftUI redraw —
    /// which, mid-download, is several times a second.
    var queueSummary: QueueSummary {
        var linkCount = 0
        var totalFiles = 0
        var totalBytes: Int64 = 0
        for item in queue where item.status == .ready {
            linkCount += 1
            totalFiles += item.analysis.fileCount ?? 1
            totalBytes += item.analysis.totalBytes ?? 0
        }
        let estimatedSeconds = totalBytes > 0 ? Double(totalBytes) / Self.assumedDownloadRateBytesPerSecond : nil
        return QueueSummary(linkCount: linkCount, totalFiles: totalFiles, totalBytes: totalBytes, estimatedSeconds: estimatedSeconds)
    }

    private var hasReadyItems: Bool { queue.contains { $0.status == .ready } }

    /// True when a card is on screen that carries its own destination row and
    /// its own Download button, so the paste box can stop offering both.
    var hasActiveAnalysisCard: Bool {
        switch linkAnalysisState {
        case .analyzed, .batchReview, .duplicateCompleted: true
        default: false
        }
    }

    var canStartQueue: Bool {
        hasReadyItems && selectedDestinationURL != nil && !isQueueProcessing && !isSigningIn
    }

    var attentionItems: [QueueItem] {
        queue.filter { item in
            if item.status == .failed || item.status == .waiting { return true }
            guard item.status == .ready, let destination = item.destinationURL else { return false }
            return !FileManager.default.fileExists(atPath: destination.path)
        }
    }

    /// Fills an otherwise-empty link field from the current clipboard. This is
    /// deliberately event-driven (only when the user opens DropDrive), so the
    /// app never polls or retains unrelated clipboard contents in the background.
    /// Analysis may begin, but downloads still require the normal review action.
    @discardableResult
    func importClipboardLinksIfAppropriate() -> Bool {
        guard driveLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !hasActiveAnalysisCard,
              !isSigningIn else { return false }

        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastImportedClipboardChangeCount else { return false }

        let links = ClipboardLinkReader.links(from: pasteboard)
        guard !links.isEmpty else { return false }

        lastImportedClipboardChangeCount = pasteboard.changeCount
        driveLink = links.joined(separator: "\n")
        return true
    }

    private func installRecoveryObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.didMountNotification] {
            recoveryObserverTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recoverAvailableDestinations() }
            })
        }
    }

    private func recoverAvailableDestinations() {
        capacityCache = nil
        if selectedDestinationURL == nil {
            selectedDestinationURL = DestinationStore.restore() ?? PreferencesStore.shared.defaultDownloadFolderURL
        }
        for index in queue.indices where queue[index].status == .waiting && queue[index].attentionKind == .destination {
            guard let destination = queue[index].destinationURL,
                  FileManager.default.fileExists(atPath: destination.path) else { continue }
            queue[index].status = .ready
            queue[index].attentionKind = nil
            queue[index].nextRetryAt = nil
            clearAttention(for: queue[index].id)
        }
        QueueStore.save(queue)
        processQueueIfNeeded()
    }

    func preflight(for analysis: DriveLinkAnalysis) -> DestinationPreflight {
        let capacity = cachedDestinationCapacity()
        let canQueue: Bool
        switch capacity {
        case .notSelected, .unavailable:
            canQueue = false
        case .unknown:
            // A number of writable SMB/NAS volumes report zero when capacity is
            // unavailable. Let the download proceed and rely on write errors
            // rather than turning an unknown value into a disabled button.
            canQueue = true
        case .available(let free):
            if let bytes = analysis.totalBytes {
                canQueue = free >= Self.requiredCapacity(for: bytes)
            } else {
                canQueue = free >= Self.unknownSizeFloorBytes
            }
        }
        guard let destination = selectedDestinationURL else {
            return DestinationPreflight(capacity: capacity, requiredBytes: analysis.totalBytes, hasNameCollision: false, canQueue: canQueue)
        }
        let candidate = destination.appendingPathComponent(analysis.name, isDirectory: analysis.type == .folder)
        return DestinationPreflight(
            capacity: capacity,
            requiredBytes: analysis.totalBytes,
            hasNameCollision: FileManager.default.fileExists(atPath: candidate.path),
            canQueue: canQueue
        )
    }

    func restoreLogin() {
        Task {
            googleAccount = await loginManager.restoreSavedAccount()
            // The cached copy is shown first so the chip doesn't sit empty, then
            // corrected if the profile has moved on since sign-in.
            if let refreshed = await loginManager.refreshSavedAccount() {
                googleAccount = refreshed
            }
        }
    }

    func signInWithGoogle() {
        Task {
            isSigningIn = true
            defer { isSigningIn = false }

            do {
                let account = try await loginManager.signIn()
                googleAccount = account

                // Re-run analysis for whatever is in the field now that there's a
                // session. Restoring `pendingDownloadLink` can't be what triggers
                // that: the link never left the text field, so assigning it back
                // writes the value it already had, and `driveLink`'s didSet
                // deliberately ignores no-op writes — which left the view stuck on
                // "needs connection" after a successful sign-in until the app was
                // relaunched and the link pasted again. Kick it off explicitly.
                if let pending = pendingDownloadLink {
                    driveLink = pending
                    pendingDownloadLink = nil
                }
                scheduleAnalysis()
            } catch {
                // Sign-in was cancelled or failed; the Connect button simply
                // becomes available again for the user to retry.
            }
        }
    }

    func signOut() {
        loginManager.signOut()
        googleAccount = nil
        Task { await downloadService.clearAnalysisCache() }
    }

    /// Entry point for every URL the app is opened with: Google Sign-In's OAuth
    /// callback, or `dropdrive://download?url=<supported link>` from the Share
    /// extension and other integrations. The host segment
    /// isn't actually inspected below, so any `dropdrive://<host>?url=...` works,
    /// but `download` is the one canonical form every integration emits.
    ///
    /// A multi-selection arrives as several `url` query items on the same deep
    /// link (`?url=A&url=B&url=C`) rather than a second endpoint — still the one
    /// `dropdrive://download?url=` form, just repeated.
    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.caseInsensitiveCompare("dropdrive") == .orderedSame else {
            return
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let links = (components.queryItems ?? [])
            .filter { $0.name == "url" }
            .compactMap { $0.value }
            .filter { !$0.isEmpty }
        guard !links.isEmpty else { return }

        NSApp.activate(ignoringOtherApps: true)

        if links.count == 1 {
            driveLink = links[0]
            handleSubmit()
        } else {
            Task { await enqueueBatch(links) }
        }
    }

    /// Links handed in from outside the paste box — the phone inbox or the
    /// right-click Service. Analyzed and queued silently (video links included,
    /// full-video mode), a notification confirms what arrived, and the queue
    /// starts on its own if idle — the sender isn't looking at the window.
    func receiveExternalLinks(
        _ links: [String],
        sourceLabel: String,
        autoStart: Bool = true,
        notify: Bool = true
    ) async -> ExternalLinkReceipt {
        var receipt = ExternalLinkReceipt()
        var queuedNames: [String] = []
        let downloadService = self.downloadService
        let videoDownloadService = self.videoDownloadService
        let work = await BoundedAsyncMap.run(links, limit: Self.batchAnalysisConcurrency) { link in
            await Self.analyzeBatchLink(
                link,
                downloadService: downloadService,
                videoDownloadService: videoDownloadService
            )
        }

        for item in work {
            switch item.result {
            case .ready(let analysis):
                if queue.contains(where: { $0.itemID == analysis.itemID })
                    || DownloadHistoryStore.shared.hasCompleted(itemID: analysis.itemID) {
                    receipt.duplicates += 1
                } else {
                    enqueue(analysis: analysis, driveLink: item.link)
                    queuedNames.append(analysis.name)
                    receipt.queued += 1
                }
            case .unsupported:
                receipt.unsupported += 1
            case .needsConnection, .videoUnavailable, .failed:
                receipt.retryableFailures += 1
                receipt.retryableLinks.append(item.link)
            }
        }

        if notify, queuedNames.isEmpty, receipt.retryableFailures + receipt.unsupported > 0 {
            NotificationService.notify(
                title: tr("Couldn't use the link \(sourceLabel)", "ใช้ลิงก์\(sourceLabel)ไม่ได้"),
                body: receipt.retryableFailures > 0
                    ? tr("DropDrive will keep it and retry when the connection or sign-in is ready.", "DropDrive จะเก็บลิงก์ไว้และลองใหม่เมื่อเน็ตหรือการลงชื่อเข้าใช้พร้อม")
                    : tr("This link is not supported. The original will be kept in Rejected.", "ไม่รองรับลิงก์นี้ โดยจะเก็บต้นฉบับไว้ในโฟลเดอร์ Rejected")
            )
        } else if notify, !queuedNames.isEmpty {
            NotificationService.notify(
                title: tr("Link received \(sourceLabel)", "รับลิงก์\(sourceLabel)แล้ว"),
                body: queuedNames.count == 1
                    ? queuedNames[0]
                    : tr("\(queuedNames.count) items queued", "เข้าคิว \(queuedNames.count) รายการ")
            )
        }

        if autoStart, receipt.queued > 0, !isQueueProcessing { startQueueDownloads() }
        return receipt
    }

    /// Analyzes and enqueues several links in order, silently (no inline analysis
    /// UI, no duplicate-redownload prompt) — used for a multi-file/folder selection
    /// handed off in one deep link. Items that fail to analyze (invalid, needs
    /// sign-in, already downloaded) are simply skipped rather than interrupting the
    /// rest of the batch.
    private func enqueueBatch(_ links: [String]) async {
        _ = await receiveExternalLinks(
            links,
            sourceLabel: tr("from the browser", "จากเบราว์เซอร์"),
            autoStart: false,
            notify: false
        )
    }

    func chooseDestinationFolder() {
        Task {
            isChoosingDestination = true
            defer { isChoosingDestination = false }

            guard let folderURL = await folderSelectionService.chooseDestinationFolder() else {
                return
            }

            selectedDestinationURL = folderURL
            capacityCache = nil
            DestinationStore.save(folderURL)
        }
    }

    func selectDestinationFolder(_ folderURL: URL) {
        selectedDestinationURL = folderURL
        capacityCache = nil
        DestinationStore.save(folderURL)
    }

    func changeDestination(for queueItemID: UUID) {
        Task {
            guard let folderURL = await folderSelectionService.chooseDestinationFolder(),
                  let index = queue.firstIndex(where: { $0.id == queueItemID }) else { return }
            selectedDestinationURL = folderURL
            queue[index].destinationURL = folderURL
            if queue[index].status == .waiting, queue[index].attentionKind == .destination {
                queue[index].status = .ready
                queue[index].attentionKind = nil
                queue[index].errorMessage = nil
                queue[index].nextRetryAt = nil
                clearAttention(for: queue[index].id)
            }
            capacityCache = nil
            DestinationStore.save(folderURL)
            QueueStore.save(queue)
            processQueueIfNeeded()
        }
    }

    // MARK: - Link analysis

    private func scheduleAnalysis() {
        analysisTask?.cancel()
        linkAnalysisState = .idle

        let trimmed = driveLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let suggestedDestination = DestinationStore.destinationRule(forLink: trimmed) {
            selectedDestinationURL = suggestedDestination
            capacityCache = nil
        }

        let links = SupportedLinkExtractor.links(from: trimmed)
        if links.count > 1 {
            analysisTask = Task {
                try? await Task.sleep(for: .milliseconds(70))
                guard !Task.isCancelled else { return }
                await runBatchAnalysis(for: links)
            }
            return
        }

        analysisTask = Task {
            // A paste is a committed value, not a search query. This still
            // coalesces browser paste events while removing the perceptible
            // half-second wait before analysis starts.
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled else { return }
            await runAnalysis(for: trimmed)
        }
    }

    private func runAnalysis(for trimmedLink: String) async {
        if VideoDownloadService.isSupportedLink(trimmedLink) {
            await runVideoAnalysis(for: trimmedLink)
            return
        }

        guard let itemID = GoogleDriveLinkParser.itemID(from: trimmedLink) else {
            linkAnalysisState = .invalidLink
            return
        }

        linkAnalysisState = .analyzing

        do {
            let resourceKey = GoogleDriveLinkParser.resourceKey(from: trimmedLink)
            let result = try await downloadService.analyzeLink(itemID: itemID, resourceKey: resourceKey)
            guard !Task.isCancelled else { return }

            switch result {
            case .success(let analysis):
                handleSuccessfulAnalysis(analysis, trimmedLink: trimmedLink)
            case .needsAuthentication:
                // Store link to retry after login succeeds
                pendingDownloadLink = trimmedLink
                linkAnalysisState = .needsConnection
            }
        } catch {
            guard !Task.isCancelled else { return }
            linkAnalysisState = .failed(Self.friendlyMessage(for: error))
        }
    }

    /// Build a review instead of silently enqueuing a pasted list. This is kept
    /// deliberately conservative: each item gets the same reliable metadata
    /// path as a single paste, and an unreadable item remains visible rather
    /// than being dropped behind a generic batch error.
    private func runBatchAnalysis(for links: [String]) async {
        linkAnalysisState = .analyzing
        let downloadService = self.downloadService
        let videoDownloadService = self.videoDownloadService
        let work = await BoundedAsyncMap.run(links, limit: Self.batchAnalysisConcurrency) { link in
            await Self.analyzeBatchLink(
                link,
                downloadService: downloadService,
                videoDownloadService: videoDownloadService
            )
        }
        guard !Task.isCancelled else { return }

        let items = work.map { work in
            switch work.result {
            case .ready(let analysis):
                BatchLinkReview(link: work.link, isSelected: true, result: .ready(analysis))
            case .needsConnection:
                BatchLinkReview(link: work.link, isSelected: false, result: .needsConnection)
            case .unsupported:
                BatchLinkReview(link: work.link, isSelected: false, result: .unavailable(tr("Unsupported link", "ไม่รองรับลิงก์นี้")))
            case .videoUnavailable:
                BatchLinkReview(link: work.link, isSelected: false, result: .unavailable(tr("Couldn't read this video link.", "อ่านลิงก์วิดีโอนี้ไม่ได้")))
            case .failed(let failure):
                BatchLinkReview(link: work.link, isSelected: false, result: .unavailable(Self.friendlyMessage(for: failure)))
            }
        }
        linkAnalysisState = .batchReview(items)
    }

    private nonisolated static func analyzeBatchLink(
        _ link: String,
        downloadService: any DownloadServicing,
        videoDownloadService: VideoDownloadService
    ) async -> BatchWork {
        if VideoDownloadService.isSupportedLink(link) {
            let analysis = await videoDownloadService.quickAnalyze(link)
            return BatchWork(link: link, result: analysis.map(BatchWorkResult.ready) ?? .videoUnavailable)
        }

        guard let itemID = GoogleDriveLinkParser.itemID(from: link) else {
            return BatchWork(link: link, result: .unsupported)
        }

        do {
            let result = try await downloadService.analyzeLink(
                itemID: itemID,
                resourceKey: GoogleDriveLinkParser.resourceKey(from: link)
            )
            switch result {
            case .success(let analysis): return BatchWork(link: link, result: .ready(analysis))
            case .needsAuthentication: return BatchWork(link: link, result: .needsConnection)
            }
        } catch {
            return BatchWork(link: link, result: .failed(Self.failure(for: error)))
        }
    }

    /// TikTok/YouTube/Facebook links go through yt-dlp for their metadata; the
    /// result feeds the same analyzed-card confirm flow as a Drive link.
    private func runVideoAnalysis(for trimmedLink: String) async {
        linkAnalysisState = .analyzing

        // oEmbed answers in well under a second where yt-dlp takes ~12, so the
        // card appears immediately; duration and size arrive right after.
        if let quick = await videoDownloadService.quickAnalyze(trimmedLink) {
            guard !Task.isCancelled else { return }
            handleSuccessfulAnalysis(quick, trimmedLink: trimmedLink)
            enrichVideoAnalysis(for: trimmedLink, itemID: quick.itemID)
            return
        }

        do {
            let analysis = try await videoDownloadService.analyze(trimmedLink)
            guard !Task.isCancelled else { return }
            handleSuccessfulAnalysis(analysis, trimmedLink: trimmedLink)
        } catch {
            guard !Task.isCancelled else { return }
            let message = (error as? VideoDownloadService.VideoError)?.message
                ?? tr("Couldn't read this video link.", "อ่านลิงก์วิดีโอนี้ไม่ได้")
            linkAnalysisState = .failed(message)
        }
    }

    /// Fills the already-shown card with the details oEmbed can't provide
    /// (duration, approximate size). Silently gives up if it fails or if the
    /// user has moved on — the card is already usable without them.
    private func enrichVideoAnalysis(for link: String, itemID: String) {
        enrichmentTask?.cancel()
        enrichmentTask = Task { [weak self] in
            guard let self, let full = try? await videoDownloadService.analyze(link) else { return }
            guard !Task.isCancelled else { return }
            // Wait out an open folder panel rather than rebuilding the card
            // while the user is looking at a modal on top of it.
            while isChoosingDestination {
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
            }
            // Only swap in if that same card is still on screen and untouched —
            // both analyses share the "video:<link>" item ID.
            guard case .analyzed(let shown) = linkAnalysisState, shown.itemID == itemID else { return }
            linkAnalysisState = .analyzed(full)
        }
    }

    /// Each successful analysis becomes one queue item, unless its Drive item ID is
    /// already in the queue: a still-active duplicate is highlighted and rejected, a
    /// completed one asks whether to queue a fresh copy. `reportInline` gates the
    /// paste-box UI state (analysis card, highlight, clearing the field) — off for
    /// a batch add from a multi-selection deep link, where a duplicate is simply
    /// skipped rather than surfaced as a prompt.
    private func handleSuccessfulAnalysis(_ analysis: DriveLinkAnalysis, trimmedLink: String, reportInline: Bool = true) {
        if DestinationStore.destinationRule(forLink: trimmedLink) == nil,
           let category = DestinationStore.category(for: analysis),
           let categoryDestination = DestinationStore.destinationRule(forCategory: category) {
            selectedDestinationURL = categoryDestination
            capacityCache = nil
        }
        if let existing = queue.first(where: { $0.itemID == analysis.itemID }) {
            guard reportInline else { return }
            if existing.status == .completed {
                linkAnalysisState = .duplicateCompleted(analysis)
            } else {
                // Clearing the field first, deliberately: `driveLink`'s didSet
                // reschedules analysis, which resets the state to `.idle`. Doing
                // it after setting `.duplicateActive` wiped that state in the
                // same turn, so the "Already in queue" card never appeared at
                // all — the pasted link just vanished with no explanation.
                driveLink = ""
                linkAnalysisState = .duplicateActive
                flashDuplicate(itemID: analysis.itemID)
            }
            return
        }

        if hasCompletedDownloadPreviously(itemID: analysis.itemID) {
            guard reportInline else { return }
            linkAnalysisState = .duplicateCompleted(analysis)
            return
        }

        if reportInline {
            // Show the result and wait for an explicit confirm — the user may
            // still want to change the destination folder for this item.
            linkAnalysisState = .analyzed(analysis)
        } else {
            enqueue(analysis: analysis, driveLink: trimmedLink)
        }
    }

    /// The queue remains the single download engine, but it stays an
    /// implementation detail when nothing else is pending: a lone confirmed
    /// item begins immediately. Existing work keeps the new item behind it.
    func confirmAnalyzedDownload(
        asAudio: Bool = false,
        clipSection: String? = nil,
        customName: String? = nil,
        selectedFileIDs: Set<String>? = nil,
        videoQuality: DriveLinkAnalysis.VideoQuality = .automatic,
        subtitleMode: DriveLinkAnalysis.SubtitleMode = .none,
        splitChapters: Bool = false,
        saveThumbnail: Bool = false,
        selectedMediaIndexes: Set<Int>? = nil
    ) {
        guard case .analyzed(let analysis) = linkAnalysisState else { return }
        confirmDownload(
            analysis: analysis,
            asAudio: asAudio,
            clipSection: clipSection,
            customName: customName,
            selectedFileIDs: selectedFileIDs,
            videoQuality: videoQuality,
            subtitleMode: subtitleMode,
            splitChapters: splitChapters,
            saveThumbnail: saveThumbnail,
            selectedMediaIndexes: selectedMediaIndexes
        )
    }

    private func confirmDownload(
        analysis: DriveLinkAnalysis,
        asAudio: Bool,
        clipSection: String?,
        customName: String?,
        selectedFileIDs: Set<String>?,
        videoQuality: DriveLinkAnalysis.VideoQuality,
        subtitleMode: DriveLinkAnalysis.SubtitleMode,
        splitChapters: Bool,
        saveThumbnail: Bool,
        selectedMediaIndexes: Set<Int>?
    ) {
        let startsImmediately = confirmationStartsImmediately
        let trimmedLink = driveLink.trimmingCharacters(in: .whitespacesAndNewlines)
        enqueue(
            analysis: analysis,
            driveLink: trimmedLink,
            asAudio: asAudio,
            clipSection: clipSection,
            customName: Self.usableCustomName(customName, original: analysis.name),
            selectedFileIDs: selectedFileIDs,
            videoQuality: videoQuality,
            subtitleMode: subtitleMode,
            splitChapters: splitChapters,
            saveThumbnail: saveThumbnail,
            selectedMediaIndexes: selectedMediaIndexes
        )
        driveLink = ""
        linkAnalysisState = .idle
        if startsImmediately { startQueueDownloads() }
    }

    /// Checks Recent Downloads (which spans past app sessions), not just this
    /// session's in-memory queue.
    private func hasCompletedDownloadPreviously(itemID: String) -> Bool {
        DownloadHistoryStore.shared.hasCompleted(itemID: itemID)
    }

    private func flashDuplicate(itemID: String) {
        guard let match = queue.first(where: { $0.itemID == itemID }) else { return }
        highlightedQueueItemID = match.id
        highlightTask?.cancel()
        highlightTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            if highlightedQueueItemID == match.id {
                highlightedQueueItemID = nil
            }
        }
    }

    /// Cancels whatever analysis/prompt is currently shown and clears the input field.
    /// Used by Escape, every card's Cancel button, and the invalid/duplicate states.
    func cancelAnalysis() {
        analysisTask?.cancel()
        enrichmentTask?.cancel()
        linkAnalysisState = .idle
        driveLink = ""
    }

    func toggleBatchSelection(for link: String) {
        guard case .batchReview(var items) = linkAnalysisState,
              let index = items.firstIndex(where: { $0.link == link }) else { return }
        guard case .ready = items[index].result else { return }
        items[index].isSelected.toggle()
        linkAnalysisState = .batchReview(items)
    }

    func addSelectedBatchToQueue() {
        guard case .batchReview(let items) = linkAnalysisState,
              selectedDestinationURL != nil else { return }
        let startsImmediately = confirmationStartsImmediately
        var addedAnyItem = false
        for item in items where item.isSelected {
            guard case .ready(let analysis) = item.result,
                  !queue.contains(where: { $0.itemID == analysis.itemID }),
                  !hasCompletedDownloadPreviously(itemID: analysis.itemID)
            else { continue }
            enqueue(analysis: analysis, driveLink: item.link)
            addedAnyItem = true
        }
        driveLink = ""
        linkAnalysisState = .idle
        if startsImmediately, addedAnyItem { startQueueDownloads() }
    }

    func retryAnalysis() {
        scheduleAnalysis()
    }

    func confirmDuplicateRedownload(
        asAudio: Bool = false,
        clipSection: String? = nil,
        customName: String? = nil,
        selectedFileIDs: Set<String>? = nil,
        videoQuality: DriveLinkAnalysis.VideoQuality = .automatic,
        subtitleMode: DriveLinkAnalysis.SubtitleMode = .none,
        splitChapters: Bool = false,
        saveThumbnail: Bool = false,
        selectedMediaIndexes: Set<Int>? = nil
    ) {
        guard case .duplicateCompleted(let analysis) = linkAnalysisState else { return }
        confirmDownload(
            analysis: analysis,
            asAudio: asAudio,
            clipSection: clipSection,
            customName: customName,
            selectedFileIDs: selectedFileIDs,
            videoQuality: videoQuality,
            subtitleMode: subtitleMode,
            splitChapters: splitChapters,
            saveThumbnail: saveThumbnail,
            selectedMediaIndexes: selectedMediaIndexes
        )
    }

    /// The download button / Return key: confirms an already-analyzed link, or
    /// bypasses the debounce and analyzes immediately otherwise.
    func handleSubmit() {
        // Return does *not* confirm an analysed card from here. The card owns
        // the MP3/trim/name choices in its own state, and this path can't see
        // any of them — pressing Return used to queue the item as if none of
        // them had been made, silently discarding them. The card's own Download
        // button is the default action instead, so Return still works and
        // carries what was chosen.
        guard !hasActiveAnalysisCard else { return }

        let trimmed = driveLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let links = SupportedLinkExtractor.links(from: trimmed)

        analysisTask?.cancel()
        analysisTask = Task {
            if links.count > 1 {
                await runBatchAnalysis(for: links)
            } else {
                await runAnalysis(for: trimmed)
            }
        }
    }

    // MARK: - Queue

    /// A typed name only counts when it is non-empty and actually different from
    /// the name the link already has — otherwise the item carries a "rename" that
    /// renames nothing, which then has to be reasoned about everywhere else.
    private static func usableCustomName(_ typed: String?, original: String) -> String? {
        guard let trimmed = typed?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != original,
              trimmed != (original as NSString).deletingPathExtension
        else { return nil }
        return trimmed
    }

    @discardableResult
    private func enqueue(
        analysis: DriveLinkAnalysis,
        driveLink: String,
        asAudio: Bool = false,
        clipSection: String? = nil,
        customName: String? = nil,
        selectedFileIDs: Set<String>? = nil,
        videoQuality: DriveLinkAnalysis.VideoQuality? = nil,
        subtitleMode: DriveLinkAnalysis.SubtitleMode? = nil,
        splitChapters: Bool? = nil,
        saveThumbnail: Bool? = nil,
        selectedMediaIndexes: Set<Int>? = nil
    ) -> UUID {
        let item = QueueItem(
            driveLink: driveLink,
            analysis: analysis.selectingFolderItems(selectedFileIDs),
            destinationURL: selectedDestinationURL,
            asAudio: asAudio ? true : nil,
            clipSection: clipSection,
            customName: customName,
            selectedFileIDs: selectedFileIDs,
            videoQuality: videoQuality,
            subtitleMode: subtitleMode,
            splitChapters: splitChapters,
            saveThumbnail: saveThumbnail,
            selectedMediaIndexes: selectedMediaIndexes
        )
        queue.append(item)
        QueueStore.save(queue)
        return item.id
    }

    /// Breathing room on top of the download itself, so a download can never take
    /// the volume to its last byte (macOS gets unhappy well before zero).
    private static let maximumDiskSpaceHeadroomBytes: Int64 = 2 * 1024 * 1024 * 1024
    private static let minimumDiskSpaceHeadroomBytes: Int64 = 64 * 1024 * 1024
    /// Required free space when the download's size is unknown — video links are
    /// confirmed from oEmbed data, which carries no size at all, and those used
    /// to skip the check entirely.
    private static let unknownSizeFloorBytes: Int64 = 5 * 1024 * 1024 * 1024

    /// Small downloads should not require an unrelated 2 GB of free space.
    /// Reserve 10% with sensible 64 MB–2 GB bounds instead.
    private static func requiredCapacity(for bytes: Int64) -> Int64 {
        let headroom = min(
            Self.maximumDiskSpaceHeadroomBytes,
            max(Self.minimumDiskSpaceHeadroomBytes, bytes / 10)
        )
        return bytes + headroom
    }

    private func cachedDestinationCapacity() -> DestinationCapacity.State {
        guard let destination = selectedDestinationURL else { return .notSelected }
        let path = destination.standardizedFileURL.path
        if let cached = capacityCache,
           cached.path == path,
           Date().timeIntervalSince(cached.checkedAt) < 5 {
            return cached.state
        }
        let state = DestinationCapacity.inspect(destination)
        capacityCache = (path, state, .now)
        return state
    }

    func startQueueDownloads() {
        guard canStartQueue else { return }
        if let message = diskSpaceShortfall() {
            // A real panel, not a popover-attached alert — see SystemAlert.
            let openFolder = SystemAlert.inform(
                title: tr("Not enough disk space", "พื้นที่ดิสก์ไม่พอ"),
                message: message,
                confirmTitle: tr("Open destination folder", "เปิดโฟลเดอร์ปลายทาง"),
                secondaryTitle: tr("OK", "ตกลง")
            )
            if openFolder { revealDestinationForCleanup() }
            return
        }
        processQueueIfNeeded()
    }

    /// Opens the destination in Finder so the user can clear space right away.
    func revealDestinationForCleanup() {
        guard let destination = queue.first(where: { $0.status == .ready })?.destinationURL ?? selectedDestinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    /// Non-nil when the destination volume can't safely hold the pending queue —
    /// the message explains the shortfall and the download is blocked until space
    /// is freed.
    ///
    /// A download now only ever occupies the size of the files themselves
    /// (parallel ranges stream straight into the destination), so this needs no
    /// multiplier — just the total plus headroom. Downloads of unknown size
    /// (every video link, since the card is built from oEmbed data that carries
    /// no size) used to bypass the check completely, which is exactly how a disk
    /// filled up mid-download; they're now held to a minimum-free-space floor.
    private func diskSpaceShortfall() -> String? {
        let destination = queue.first(where: { $0.status == .ready })?.destinationURL ?? selectedDestinationURL
        let capacity = DestinationCapacity.inspect(destination)
        guard case .available(let free) = capacity else {
            if case .unavailable = capacity {
                return tr(
                    "The destination folder is no longer available. Choose another folder, then try again.",
                    "โฟลเดอร์ปลายทางใช้งานไม่ได้ เลือกโฟลเดอร์ใหม่แล้วลองอีกครั้ง"
                )
            }
            return nil
        }

        let known = queueSummary.totalBytes
        let freeText = Formatters.byteCount(free)

        guard known > 0 else {
            guard free < Self.unknownSizeFloorBytes else { return nil }
            return tr(
                "Only \(freeText) free on the destination disk, and this download's size isn't known yet. Free up some space first.",
                "ดิสก์ปลายทางเหลือ \(freeText) และยังไม่ทราบขนาดของงานนี้ กรุณาเคลียร์พื้นที่ก่อน"
            )
        }

        let required = Self.requiredCapacity(for: known)
        guard free < required else { return nil }

        let knownText = Formatters.byteCount(known)
        return tr(
            "This download is \(knownText), but the destination disk only has \(freeText) free. Free up some space first.",
            "งานนี้ขนาด \(knownText) แต่ดิสก์ปลายทางเหลือ \(freeText) กรุณาเคลียร์พื้นที่ก่อน"
        )
    }

    private func processQueueIfNeeded() {
        guard activeQueueItemID == nil, !isQueuePaused else { return }
        // A paused item was already in flight; give it priority over freshly-queued ones.
        let index = queue.firstIndex(where: { $0.status == .paused }) ?? queue.firstIndex(where: { $0.status == .ready })
        guard let index else { return }
        // Each item carries the destination chosen when it was queued; only items
        // persisted before that field existed fall back to the current selection.
        guard let destinationURL = queue[index].destinationURL ?? selectedDestinationURL else { return }
        startDownloading(queue[index], destinationURL: destinationURL)
    }

    private func startDownloading(_ item: QueueItem, destinationURL: URL) {
        guard let index = queue.firstIndex(where: { $0.id == item.id }) else { return }
        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            queue[index].status = .waiting
            queue[index].attentionKind = .destination
            queue[index].errorMessage = tr(
                "Waiting for the destination drive to reconnect.",
                "กำลังรอไดรฟ์ปลายทางเชื่อมต่ออีกครั้ง"
            )
            QueueStore.save(queue)
            notifyAttentionIfNeeded(for: queue[index])
            activeQueueItemID = nil
            processQueueIfNeeded()
            return
        }
        queue[index].status = .downloading
        queue[index].attentionKind = nil
        queue[index].nextRetryAt = nil
        activeQueueItemID = item.id
        activeProgress = DownloadProgress(currentFileName: "Preparing…")
        QueueStore.save(queue)

        if item.analysis.isVideo == true {
            startVideoDownload(item, destinationURL: destinationURL)
            return
        }

        let request = DownloadRequest(
            driveLink: item.driveLink,
            itemID: item.itemID,
            destinationURL: destinationURL,
            resourceKey: GoogleDriveLinkParser.resourceKey(from: item.driveLink),
            resumeID: item.id,
            customName: item.customName,
            selectedFileIDs: item.selectedFileIDs,
            selectedFolderItems: item.selectedFileIDs.map { selectedIDs in
                item.analysis.folderItems?.filter { selectedIDs.contains($0.id) } ?? []
            }
        )

        downloadTask = Task {
            let activity = DownloadActivityService.begin()
            defer { DownloadActivityService.end(activity) }
            do {
                let resultURL = try await downloadService.download(request) { progress in
                    Task { @MainActor [self] in
                        self.activeProgress = progress
                        if progress.bytesDownloaded > 0 || progress.completedFiles > 0 {
                            self.clearAttention(for: item.id)
                        }
                    }
                }
                try Task.checkCancellation()
                autoRetryAttempts[item.id] = nil
                finishActiveItem(item.id, status: .completed, resultURL: resultURL, errorMessage: nil)
            } catch is CancellationError {
                let status: QueueItem.Status = isPausingActiveItem ? .paused : .cancelled
                isPausingActiveItem = false
                autoRetryAttempts[item.id] = nil
                finishActiveItem(item.id, status: status, resultURL: nil, errorMessage: nil)
            } catch {
                // A network drop retries itself a few times with backoff before
                // giving up — resume data is kept, so each retry continues from
                // where the connection died rather than starting over.
                let attempts = autoRetryAttempts[item.id, default: 0]
                if error is URLError, attempts < Self.autoRetryDelays.count {
                    scheduleAutoRetry(item, destinationURL: destinationURL, attempt: attempts + 1)
                } else {
                    autoRetryAttempts[item.id] = nil
                    finishActiveItem(item.id, status: .failed, resultURL: nil, errorMessage: Self.friendlyMessage(for: error))
                }
            }
        }
    }

    /// Video links download through yt-dlp instead of the Drive engine; the
    /// queue mechanics (cancel/pause statuses, completion handling, retry UI)
    /// are shared. yt-dlp resumes its own .part files, so pause/resume works.
    private func startVideoDownload(_ item: QueueItem, destinationURL: URL) {
        downloadTask = Task {
            let activity = DownloadActivityService.begin()
            defer { DownloadActivityService.end(activity) }
            do {
                let resultURL = try await videoDownloadService.download(
                    link: item.driveLink,
                    title: item.displayName,
                    destination: destinationURL,
                    asAudio: item.asAudio == true,
                    clipSection: item.clipSection,
                    customName: item.customName,
                    quality: item.videoQuality ?? (item.asAudio == true ? .mp3 : .automatic),
                    subtitleMode: item.subtitleMode ?? .none,
                    splitChapters: item.splitChapters == true,
                    saveThumbnail: item.saveThumbnail == true,
                    selectedMediaIndexes: item.selectedMediaIndexes,
                    collectionCount: item.analysis.videoDetails?.mediaItems.count ?? 0
                ) { progress in
                    Task { @MainActor [self] in
                        self.activeProgress = progress
                        if progress.bytesDownloaded > 0 {
                            self.clearAttention(for: item.id)
                        }
                    }
                }
                try Task.checkCancellation()
                finishActiveItem(item.id, status: .completed, resultURL: resultURL, errorMessage: nil)
            } catch is CancellationError {
                let status: QueueItem.Status = isPausingActiveItem ? .paused : .cancelled
                isPausingActiveItem = false
                finishActiveItem(item.id, status: status, resultURL: nil, errorMessage: nil)
            } catch {
                let message = (error as? VideoDownloadService.VideoError)?.message
                    ?? tr("The video download failed.", "ดาวน์โหลดวิดีโอไม่สำเร็จ")
                finishActiveItem(item.id, status: .failed, resultURL: nil, errorMessage: message)
            }
        }
    }

    /// Waits out the backoff with the item still active (so the queue doesn't
    /// advance past it), then restarts the same download. Cancel and pause during
    /// the wait behave exactly as they do mid-download.
    private func scheduleAutoRetry(_ item: QueueItem, destinationURL: URL, attempt: Int) {
        autoRetryAttempts[item.id] = attempt
        let delay = Self.autoRetryDelays[attempt - 1]
        if let index = queue.firstIndex(where: { $0.id == item.id }) {
            queue[index].status = .waiting
            queue[index].attentionKind = .network
            queue[index].retryCount = attempt
            queue[index].nextRetryAt = Date().addingTimeInterval(delay)
            queue[index].errorMessage = tr(
                "Connection lost — retrying automatically.",
                "เน็ตหลุด — ระบบกำลังลองใหม่ให้อัตโนมัติ"
            )
            QueueStore.save(queue)
            notifyAttentionIfNeeded(for: queue[index])
        }
        activeProgress = DownloadProgress(
            currentFileName: tr(
                "Connection lost — retrying in \(Int(delay))s (attempt \(attempt)/\(Self.autoRetryDelays.count))",
                "เน็ตหลุด — ลองใหม่ใน \(Int(delay)) วิ (ครั้งที่ \(attempt)/\(Self.autoRetryDelays.count))"
            )
        )

        downloadTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled {
                let status: QueueItem.Status = isPausingActiveItem ? .paused : .cancelled
                isPausingActiveItem = false
                autoRetryAttempts[item.id] = nil
                finishActiveItem(item.id, status: status, resultURL: nil, errorMessage: nil)
            } else {
                startDownloading(item, destinationURL: destinationURL)
            }
        }
    }

    private func finishActiveItem(_ id: UUID, status: QueueItem.Status, resultURL: URL?, errorMessage: String?) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else {
            // The row is gone — removed, or dropped by something rewriting the
            // queue while this was in flight. There is nothing to record, but
            // the active slot still has to be released: leaving it set is what
            // made the app believe a download was running forever, which hides
            // Download All, makes Pause/Resume no-ops, and holds the menu bar
            // icon on a progress ring that can never finish.
            if activeQueueItemID == id {
                activeQueueItemID = nil
                activeProgress = nil
                isPausingActiveItem = false
                autoRetryAttempts[id] = nil
                processQueueIfNeeded()
            }
            return
        }
        queue[index].status = status
        queue[index].resultURL = resultURL
        queue[index].errorMessage = errorMessage
        if status == .completed || status == .cancelled {
            queue[index].attentionKind = nil
            queue[index].retryCount = nil
            queue[index].nextRetryAt = nil
            clearAttention(for: id)
        }
        activeQueueItemID = nil
        activeProgress = nil
        QueueStore.save(queue)

        let item = queue[index]
        // Files just appeared, moved, or were cleaned up — drop the cached
        // "does this exist" answers so Recent reflects reality.
        FileStatusCache.shared.invalidate()

        switch status {
        case .completed:
            DriveFolderSnapshotStore.shared.recordCompletedFolder(
                item.analysis,
                selectedIDs: item.selectedFileIDs
            )
            if let mediaItems = item.analysis.videoDetails?.mediaItems, mediaItems.count > 1 {
                MediaCollectionSnapshotStore.shared.recordCompleted(
                    collectionID: item.analysis.itemID,
                    items: mediaItems,
                    selectedIndexes: item.selectedMediaIndexes
                )
            }
            if let resultURL {
                if PreferencesStore.shared.openFinderWhenComplete {
                    NSWorkspace.shared.activateFileViewerSelecting([resultURL])
                }
                NotificationService.notifyDownloadComplete(
                    name: resultURL.lastPathComponent,
                    folderURL: resultURL,
                    playSound: PreferencesStore.shared.playNotificationSound
                )
            }
            DownloadHistoryStore.shared.record(DownloadHistoryItem(
                name: resultURL?.lastPathComponent ?? item.displayName,
                date: .now,
                status: .completed,
                itemURL: resultURL,
                driveLink: item.driveLink,
                fileCount: item.analysis.fileCount ?? 1,
                sizeBytes: item.analysis.totalBytes
            ))
        case .failed:
            // The resume data is deliberately kept: a failure is exactly when
            // it earns its keep, and Retry reuses the same item id, so the next
            // attempt continues from where the connection died instead of
            // starting the file over. It is cleared on success, on cancel, and
            // when the item is removed.
            DownloadHistoryStore.shared.record(DownloadHistoryItem(
                name: item.displayName, date: .now, status: .failed, driveLink: item.driveLink
            ))
        case .cancelled:
            ResumeEnvelopeStore.clear(for: item.id)
            removePartialArtifacts(of: item)
            DownloadHistoryStore.shared.record(DownloadHistoryItem(
                name: item.displayName, date: .now, status: .cancelled, driveLink: item.driveLink
            ))
        case .ready, .downloading, .paused, .waiting:
            break
        }

        if status == .completed, !queue.contains(where: { $0.status == .ready || $0.status == .paused }) {
            flashCompletion()
        }

        processQueueIfNeeded()
    }

    /// A cancelled folder download leaves a partly-filled folder on disk; the user
    /// asked for cancel to mean "nothing left behind", so it's deleted (matched by
    /// the in-progress marker, never by name alone). Single files never leave
    /// partial data at the destination — their in-flight bytes live in system temp.
    private func removePartialArtifacts(of item: QueueItem) {
        guard let destinationURL = item.destinationURL ?? selectedDestinationURL else { return }
        if item.analysis.isVideo == true {
            VideoDownloadService.cleanupPartials(title: item.displayName, in: destinationURL)
        } else if item.analysis.type == .folder {
            GoogleDriveDownloadService.removePartialFolderArtifact(itemID: item.itemID, in: destinationURL)
        } else {
            // A single file stages as "<name>.dddownload" next to its
            // destination; a run that was killed rather than cancelled leaves
            // that behind in the user's own folder. Matched by this item's own
            // name — sweeping every `.dddownload` in the folder would take out
            // a different download still running into the same place.
            // The staged file carries the name the download actually wrote under,
            // which is the typed one when the item was renamed.
            GoogleDriveDownloadService.removePartialFile(
                named: GoogleDriveDownloadService.renamed(item.analysis.name, to: item.customName),
                in: destinationURL
            )
        }
    }

    private func flashCompletion() {
        showCompletionFlash = true
        completionFlashTask?.cancel()
        completionFlashTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            showCompletionFlash = false
        }
    }

    /// Cancels the active download outright; any resume data it produced is discarded.
    func cancelActiveDownload() {
        isPausingActiveItem = false
        downloadTask?.cancel()
    }

    // MARK: - Queue pause/resume

    var canPauseQueue: Bool { isQueueProcessing && !isQueuePaused }
    var canResumeQueue: Bool { isQueuePaused && queue.contains { $0.status == .paused || $0.status == .ready } }

    /// Stops the active download safely — resume data is kept when the server supports
    /// it — and prevents the queue from auto-advancing until resumed.
    func pauseQueue() {
        guard isQueueProcessing, !isQueuePaused else { return }
        isQueuePaused = true
        isPausingActiveItem = true
        downloadTask?.cancel()
    }

    /// Also the row-level Resume button, which is why this doesn't require the
    /// queue-wide flag to be set: a paused item with the flag clear is a state
    /// the app can reach (a queue restored from a previous session), and the
    /// button has to work there rather than silently doing nothing.
    func resumeQueue() {
        guard isQueuePaused || queue.contains(where: { $0.status == .paused }) else { return }
        isQueuePaused = false
        processQueueIfNeeded()
    }

    /// Retries only this item; the rest of the queue's order and state are untouched.
    func retryQueueItem(_ id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }),
              queue[index].status == .failed || queue[index].status == .waiting else { return }
        queue[index].status = .ready
        queue[index].errorMessage = nil
        queue[index].attentionKind = nil
        queue[index].retryCount = nil
        queue[index].nextRetryAt = nil
        clearAttention(for: id)
        QueueStore.save(queue)
        processQueueIfNeeded()
    }

    func removeQueueItem(_ id: UUID) {
        guard id != activeQueueItemID else { return }
        // Removing an unfinished item is a cancellation from the user's point of
        // view: whatever it already wrote to disk goes with it.
        if let item = queue.first(where: { $0.id == id }), item.status != .completed {
            removePartialArtifacts(of: item)
        }
        queue.removeAll { $0.id == id }
        QueueStore.save(queue)
        ResumeEnvelopeStore.clear(for: id)
        autoRetryAttempts[id] = nil
        clearAttention(for: id)
    }

    private func notifyAttentionIfNeeded(for item: QueueItem) {
        guard let kind = item.attentionKind,
              kind == .network || kind == .destination,
              notifiedAttentionItemIDs.insert(item.id).inserted else { return }
        NotificationService.notifyAttention(itemID: item.id, name: item.displayName, kind: kind)
    }

    private func clearAttention(for id: UUID) {
        notifiedAttentionItemIDs.remove(id)
        NotificationService.clearAttention(itemID: id)
    }

    func clearCompletedQueueItems() {
        queue.removeAll { $0.status == .completed }
        QueueStore.save(queue)
    }

    /// A completed row remains actionable: create a fresh queue entry instead
    /// of mutating history or pretending the existing finished item can run
    /// again. The destination and video choices are kept with the new entry.
    func downloadAgain(_ id: UUID) {
        guard let item = queue.first(where: { $0.id == id && $0.status == .completed }) else { return }
        queue.append(QueueItem(
            driveLink: item.driveLink,
            analysis: item.analysis,
            destinationURL: item.destinationURL ?? selectedDestinationURL,
            asAudio: item.asAudio,
            clipSection: item.clipSection,
            customName: item.customName,
            selectedFileIDs: item.selectedFileIDs
        ))
        QueueStore.save(queue)
    }

    /// Reorders pending (`.ready`) items via drag-and-drop; the active download and
    /// completed/failed rows are left untouched.
    func moveQueueItem(fromID: UUID, toID: UUID) {
        guard fromID != toID,
              let fromIndex = queue.firstIndex(where: { $0.id == fromID }), queue[fromIndex].status == .ready,
              queue.first(where: { $0.id == toID })?.status == .ready else { return }

        let item = queue.remove(at: fromIndex)
        let insertionIndex = queue.firstIndex(where: { $0.id == toID }) ?? queue.count
        queue.insert(item, at: insertionIndex)
        QueueStore.save(queue)
    }

    // MARK: - Queue persistence / restore

    private func checkForSavedQueue() {
        guard let saved = QueueStore.load(), !saved.isEmpty else { return }
        pendingRestoreQueue = saved
    }

    /// Asked the first time the user opens the window, not at launch. Launch is
    /// the wrong moment for a modal: with "launch at login" on it would ambush
    /// them at every boot, and an agent app has no window for it to belong to.
    func promptForSavedQueueIfNeeded() {
        guard let saved = pendingRestoreQueue, !saved.isEmpty, !hasAskedAboutRestore else { return }
        hasAskedAboutRestore = true

        let count = saved.count
        let restore = SystemAlert.confirm(
            title: tr("Restore previous queue?", "กู้คืนคิวจากครั้งก่อน?"),
            message: tr(
                "You have \(count) item\(count == 1 ? "" : "s") from your last session.",
                "มี \(count) รายการค้างจากครั้งที่แล้ว"
            ),
            confirmTitle: tr("Restore", "กู้คืน"),
            cancelTitle: tr("Discard", "ทิ้งไป")
        )
        if restore { restoreSavedQueue() } else { discardSavedQueue() }
    }

    /// A queue item that was mid-download when the app last quit never finished;
    /// it's restored as ready so the engine can pick it back up from scratch.
    ///
    /// A *paused* one is restored as ready too, and has to be: "paused" is a
    /// state of this session's queue, not of the item, and the flag holding the
    /// queue paused doesn't survive a relaunch. Left as paused, the row's Resume
    /// button ran into `resumeQueue`'s "only when the queue is paused" guard and
    /// did nothing, "Resume all" never appeared because that reads the same
    /// flag, and "Download All" never appeared either because nothing was
    /// `.ready` — a restored queue of paused items could not be started at all.
    /// Resume data is keyed by the item's id and is untouched by this, so each
    /// one still continues from where it stopped rather than restarting.
    /// Merged into the live queue, never assigned over it. The prompt this
    /// answers is raised the first time the window is opened, not at launch, and
    /// a download can already be running by then: a link from the phone inbox or
    /// the right-click Service starts one without the window ever being opened.
    /// Replacing the array dropped that item while `activeQueueItemID` still
    /// pointed at it, and when it finished `finishActiveItem` found no matching
    /// row and returned before clearing the active state — leaving the app
    /// permanently "downloading", with no control able to start anything else.
    func restoreSavedQueue() {
        guard var saved = pendingRestoreQueue else { return }
        for index in saved.indices where saved[index].status == .downloading || saved[index].status == .paused || saved[index].status == .waiting {
            saved[index].status = .ready
            saved[index].attentionKind = nil
            saved[index].nextRetryAt = nil
        }
        let liveIDs = Set(queue.map(\.id))
        queue.append(contentsOf: saved.filter { !liveIDs.contains($0.id) })
        pendingRestoreQueue = nil
        QueueStore.save(queue)
    }

    func discardSavedQueue() {
        pendingRestoreQueue = nil
        QueueStore.clear()
    }

    /// Every message a failed download can show. The goal is that the row itself
    /// says what to do about it — a disk that filled up mid-download used to
    /// surface as "Something went wrong", leaving the user to work out the cause
    /// on their own.
    private static func friendlyMessage(for error: Error) -> String {
        friendlyMessage(for: failure(for: error))
    }

    private nonisolated static func failure(for error: Error) -> FriendlyFailure {
        if isOutOfSpace(error) { return .outOfSpace }
        if let driveError = error as? DriveDownloadError {
            switch driveError {
            case .server(let statusCode, _): return .driveServer(statusCode)
            case .invalidResponse: return .driveInvalidResponse
            case .unsupportedFileType: return .driveUnsupported
            case .integrityMismatch: return .integrity
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost: return .offline
            case .timedOut: return .timedOut
            default: return .network
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain || nsError.domain == NSCocoaErrorDomain { return .write }
        return .other
    }

    private static func friendlyMessage(for failure: FriendlyFailure) -> String {
        switch failure {
        case .outOfSpace:
            return tr(
                "The disk is full. Free up some space, then retry.",
                "พื้นที่ดิสก์เต็ม กรุณาเคลียร์พื้นที่แล้วกดลองใหม่"
            )
        case .driveServer(let statusCode):
            switch statusCode {
                case 404:
                    return tr(
                        "This link doesn't point to an existing Google Drive file or folder.",
                        "ลิงก์นี้ไม่ตรงกับไฟล์หรือโฟลเดอร์ที่มีอยู่ใน Google Drive"
                    )
                case 403:
                    return tr(
                        "You don't have permission to access this item.",
                        "คุณไม่มีสิทธิ์เข้าถึงรายการนี้"
                    )
                case 429:
                    return tr(
                        "Google Drive is rate-limiting downloads right now. Wait a few minutes, then retry.",
                        "Google Drive กำลังจำกัดการดาวน์โหลด รอสักครู่แล้วกดลองใหม่"
                    )
                case 500...599:
                    return tr(
                        "Google Drive is having trouble right now. Retry in a moment.",
                        "Google Drive ขัดข้องชั่วคราว รอสักครู่แล้วลองใหม่"
                    )
                default:
                    return tr(
                        "Google Drive couldn't process this link right now.",
                        "Google Drive ประมวลผลลิงก์นี้ไม่ได้ในตอนนี้"
                    )
            }
        case .driveInvalidResponse:
            return tr("Google Drive sent back something unexpected. Retry in a moment.", "Google Drive ตอบกลับผิดปกติ รอสักครู่แล้วลองใหม่")
        case .driveUnsupported:
            return tr("This file type can't be downloaded directly from Google Drive.", "ไฟล์ชนิดนี้ดาวน์โหลดตรงจาก Google Drive ไม่ได้")
        case .integrity:
            return tr(
                "The file didn't match Google Drive's checksum, so the incomplete copy was removed. Retry the download.",
                "ไฟล์ไม่ตรงกับ checksum ของ Google Drive จึงลบสำเนาที่ไม่สมบูรณ์แล้ว กรุณาลองดาวน์โหลดอีกครั้ง"
            )
        case .offline:
            return tr("The internet connection dropped. It will retry automatically.", "เน็ตหลุด ระบบจะลองใหม่ให้อัตโนมัติ")
        case .timedOut:
            return tr("The connection timed out. Check your internet, then retry.", "การเชื่อมต่อหมดเวลา เช็คเน็ตแล้วกดลองใหม่")
        case .network:
            return tr("Check your internet connection and try again.", "เช็คการเชื่อมต่ออินเทอร์เน็ตแล้วลองใหม่")
        case .write:
            return tr(
                "Couldn't write the file to the destination folder. Check the folder still exists and has space.",
                "เขียนไฟล์ลงโฟลเดอร์ปลายทางไม่ได้ ตรวจสอบว่าโฟลเดอร์ยังอยู่และมีพื้นที่พอ"
            )
        case .other:
            return tr("Something went wrong. Please try again.", "เกิดข้อผิดพลาด กรุณาลองใหม่")
        }
    }

    /// Disk-full surfaces differently depending on which layer hit it: Foundation
    /// file writes report `NSFileWriteOutOfSpaceError`, raw POSIX writes report
    /// `ENOSPC`.
    private nonisolated static func isOutOfSpace(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError { return true }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isOutOfSpace(underlying)
        }
        return false
    }
}

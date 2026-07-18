import AppKit
import Foundation
import Observation

struct QueueSummary {
    let linkCount: Int
    let totalFiles: Int
    let totalBytes: Int64
    let estimatedSeconds: Double?
}

@MainActor
@Observable
final class DropDriveViewModel {
    /// The main window and the menu bar extra both need to reflect the same live
    /// queue/progress state, not two independent download engines — shared the same
    /// way DownloadHistoryStore/PreferencesStore are.
    static let shared = DropDriveViewModel()

    private static let largeDownloadThresholdBytes: Int64 = 1_073_741_824 // 1 GB
    private static let assumedDownloadRateBytesPerSecond: Double = 5_000_000 // conservative ~5 MB/s estimate for the ETA shown before starting

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
    var showLargeDownloadWarning = false
    var isQueuePaused = false

    var pendingRestoreQueue: [QueueItem]?
    var showRestorePrompt = false

    private let loginManager: LoginManaging
    private let downloadService: DownloadServicing
    private let folderSelectionService: FolderSelectionServicing
    private var downloadTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var highlightTask: Task<Void, Never>?
    private var isPausingActiveItem = false

    /// Auto-retry on network drops: attempts already made per queue item, and the
    /// backoff before each retry. Cleared on success, pause, cancel, or removal.
    private var autoRetryAttempts: [UUID: Int] = [:]
    private static let autoRetryDelays: [Double] = [5, 15, 45]

    /// Set for 2 seconds after the queue finishes its last item, so the menu bar
    /// icon can flash a checkmark.
    var showCompletionFlash = false
    private var completionFlashTask: Task<Void, Never>?

    init() {
        let loginManager = LoginManager.shared
        self.loginManager = loginManager
        self.downloadService = GoogleDriveDownloadService(loginManager: loginManager)
        self.folderSelectionService = FolderSelectionService()
        self.selectedDestinationURL = DestinationStore.restore() ?? PreferencesStore.shared.defaultDownloadFolderURL
        checkForSavedQueue()
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

    var readyItems: [QueueItem] { queue.filter { $0.status == .ready } }

    var queueSummary: QueueSummary {
        let items = readyItems
        let totalFiles = items.reduce(0) { $0 + ($1.analysis.fileCount ?? 1) }
        let totalBytes = items.reduce(Int64(0)) { $0 + ($1.analysis.totalBytes ?? 0) }
        let estimatedSeconds = totalBytes > 0 ? Double(totalBytes) / Self.assumedDownloadRateBytesPerSecond : nil
        return QueueSummary(linkCount: items.count, totalFiles: totalFiles, totalBytes: totalBytes, estimatedSeconds: estimatedSeconds)
    }

    var canStartQueue: Bool {
        !readyItems.isEmpty && selectedDestinationURL != nil && !isQueueProcessing && !isSigningIn
    }

    var isLargeDownload: Bool {
        queueSummary.totalBytes > Self.largeDownloadThresholdBytes
    }

    func restoreLogin() {
        Task {
            googleAccount = await loginManager.restoreSavedAccount()
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

    func handleCallbackURL(_ url: URL) {
        _ = loginManager.handleCallbackURL(url)
    }

    /// Entry point for every URL the app is opened with: Google Sign-In's OAuth
    /// callback, or `dropdrive://download?url=<Drive link>` from the Chrome
    /// extension or Share Extension — both of which hand off a
    /// link the same way rather than talking to the app directly. The host segment
    /// isn't actually inspected below, so any `dropdrive://<host>?url=...` works,
    /// but `download` is the one canonical form every integration emits.
    ///
    /// A multi-selection in the Chrome extension arrives as several `url` query
    /// items on the same deep link (`?url=A&url=B&url=C`) rather than a second
    /// endpoint — still the one `dropdrive://download?url=` form, just repeated.
    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.caseInsensitiveCompare("dropdrive") == .orderedSame else {
            handleCallbackURL(url)
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

    /// Analyzes and enqueues several links in order, silently (no inline analysis
    /// UI, no duplicate-redownload prompt) — used for a multi-file/folder selection
    /// handed off in one deep link. Items that fail to analyze (invalid, needs
    /// sign-in, already downloaded) are simply skipped rather than interrupting the
    /// rest of the batch.
    private func enqueueBatch(_ links: [String]) async {
        for link in links {
            guard let itemID = GoogleDriveLinkParser.itemID(from: link) else { continue }
            let resourceKey = GoogleDriveLinkParser.resourceKey(from: link)
            guard let result = try? await downloadService.analyzeLink(itemID: itemID, resourceKey: resourceKey),
                  case .success(let analysis) = result else { continue }
            handleSuccessfulAnalysis(analysis, trimmedLink: link, reportInline: false)
        }
    }

    func chooseDestinationFolder() {
        Task {
            guard let folderURL = await folderSelectionService.chooseDestinationFolder() else {
                return
            }

            selectedDestinationURL = folderURL
            DestinationStore.save(folderURL)
        }
    }

    // MARK: - Link analysis

    private func scheduleAnalysis() {
        analysisTask?.cancel()
        linkAnalysisState = .idle

        let trimmed = driveLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        analysisTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await runAnalysis(for: trimmed)
        }
    }

    private func runAnalysis(for trimmedLink: String) async {
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

    /// Each successful analysis becomes one queue item, unless its Drive item ID is
    /// already in the queue: a still-active duplicate is highlighted and rejected, a
    /// completed one asks whether to queue a fresh copy. `reportInline` gates the
    /// paste-box UI state (analysis card, highlight, clearing the field) — off for
    /// a batch add from a multi-selection deep link, where a duplicate is simply
    /// skipped rather than surfaced as a prompt.
    private func handleSuccessfulAnalysis(_ analysis: DriveLinkAnalysis, trimmedLink: String, reportInline: Bool = true) {
        if let existing = queue.first(where: { $0.itemID == analysis.itemID }) {
            guard reportInline else { return }
            if existing.status == .completed {
                linkAnalysisState = .duplicateCompleted(analysis)
            } else {
                linkAnalysisState = .duplicateActive
                flashDuplicate(itemID: analysis.itemID)
                driveLink = ""
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

    /// The user confirmed the analyzed link: queue it with whatever destination
    /// is selected right now, and start immediately unless something is already
    /// downloading (in which case it just lines up behind it).
    func confirmAnalyzedDownload() {
        guard case .analyzed(let analysis) = linkAnalysisState else { return }
        let trimmedLink = driveLink.trimmingCharacters(in: .whitespacesAndNewlines)
        enqueue(analysis: analysis, driveLink: trimmedLink)
        driveLink = ""
        linkAnalysisState = .idle
        if !isQueueProcessing {
            startQueueDownloads()
        }
    }

    /// Checks Recent Downloads (which spans past app sessions), not just this
    /// session's in-memory queue.
    private func hasCompletedDownloadPreviously(itemID: String) -> Bool {
        DownloadHistoryStore.shared.items.contains { historyItem in
            historyItem.status == .completed && GoogleDriveLinkParser.itemID(from: historyItem.driveLink) == itemID
        }
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
        linkAnalysisState = .idle
        driveLink = ""
    }

    func retryAnalysis() {
        scheduleAnalysis()
    }

    func confirmDuplicateRedownload() {
        guard case .duplicateCompleted(let analysis) = linkAnalysisState else { return }
        let trimmedLink = driveLink.trimmingCharacters(in: .whitespacesAndNewlines)
        enqueue(analysis: analysis, driveLink: trimmedLink)
        driveLink = ""
    }

    /// The download button / Return key: confirms an already-analyzed link, or
    /// bypasses the debounce and analyzes immediately otherwise.
    func handleSubmit() {
        if case .analyzed = linkAnalysisState {
            confirmAnalyzedDownload()
            return
        }

        let trimmed = driveLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        analysisTask?.cancel()
        analysisTask = Task {
            await runAnalysis(for: trimmed)
        }
    }

    // MARK: - Queue

    private func enqueue(analysis: DriveLinkAnalysis, driveLink: String) {
        queue.append(QueueItem(driveLink: driveLink, analysis: analysis, destinationURL: selectedDestinationURL))
        QueueStore.save(queue)
    }

    var showDiskSpaceWarning = false
    var diskSpaceWarningMessage = ""

    /// Headroom on top of the download size itself, so a download can't fill the
    /// disk to the last byte even when the estimate is exact.
    private static let diskSpaceHeadroomBytes: Int64 = 200 * 1024 * 1024

    func startQueueDownloads() {
        guard canStartQueue else { return }
        if let message = diskSpaceShortfall() {
            diskSpaceWarningMessage = message
            showDiskSpaceWarning = true
            return
        }
        if isLargeDownload {
            showLargeDownloadWarning = true
        } else {
            processQueueIfNeeded()
        }
    }

    /// The user saw the free-space warning and chose to download anyway.
    func confirmDiskSpaceAndStart() {
        showDiskSpaceWarning = false
        if isLargeDownload {
            showLargeDownloadWarning = true
        } else {
            processQueueIfNeeded()
        }
    }

    func cancelDiskSpaceWarning() {
        showDiskSpaceWarning = false
    }

    /// Non-nil when the pending queue's known size won't fit in the destination
    /// volume's free space (plus headroom). Sizes Drive didn't report count as
    /// zero — better an occasional missed warning than a false one.
    private func diskSpaceShortfall() -> String? {
        let needed = queueSummary.totalBytes
        guard needed > 0,
              let destination = readyItems.first?.destinationURL ?? selectedDestinationURL,
              let values = try? destination.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = values.volumeAvailableCapacityForImportantUsage,
              free > 0,
              free < needed + Self.diskSpaceHeadroomBytes else { return nil }

        let neededText = Formatters.byteCount(needed)
        let freeText = Formatters.byteCount(free)
        return tr(
            "This download needs \(neededText), but the destination disk only has \(freeText) free.",
            "ดาวน์โหลดนี้ต้องใช้พื้นที่ \(neededText) แต่ดิสก์ปลายทางเหลือ \(freeText)"
        )
    }

    func confirmLargeDownloadAndStart() {
        showLargeDownloadWarning = false
        processQueueIfNeeded()
    }

    func cancelLargeDownloadWarning() {
        showLargeDownloadWarning = false
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
        queue[index].status = .downloading
        activeQueueItemID = item.id
        activeProgress = DownloadProgress(currentFileName: "Preparing…")
        QueueStore.save(queue)

        let request = DownloadRequest(
            driveLink: item.driveLink,
            itemID: item.itemID,
            destinationURL: destinationURL,
            resourceKey: GoogleDriveLinkParser.resourceKey(from: item.driveLink),
            resumeID: item.id
        )

        downloadTask = Task {
            do {
                let resultURL = try await downloadService.download(request) { progress in
                    Task { @MainActor [self] in
                        self.activeProgress = progress
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

    /// Waits out the backoff with the item still active (so the queue doesn't
    /// advance past it), then restarts the same download. Cancel and pause during
    /// the wait behave exactly as they do mid-download.
    private func scheduleAutoRetry(_ item: QueueItem, destinationURL: URL, attempt: Int) {
        autoRetryAttempts[item.id] = attempt
        let delay = Self.autoRetryDelays[attempt - 1]
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
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].status = status
        queue[index].resultURL = resultURL
        queue[index].errorMessage = errorMessage
        activeQueueItemID = nil
        activeProgress = nil
        QueueStore.save(queue)

        let item = queue[index]
        switch status {
        case .completed:
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
                name: resultURL?.lastPathComponent ?? item.analysis.name,
                date: .now,
                status: .completed,
                itemURL: resultURL,
                driveLink: item.driveLink,
                fileCount: item.analysis.fileCount ?? 1,
                sizeBytes: item.analysis.totalBytes
            ))
        case .failed:
            ResumeEnvelopeStore.clear(for: item.id)
            DownloadHistoryStore.shared.record(DownloadHistoryItem(
                name: item.analysis.name, date: .now, status: .failed, driveLink: item.driveLink
            ))
        case .cancelled:
            ResumeEnvelopeStore.clear(for: item.id)
            removePartialArtifacts(of: item)
            DownloadHistoryStore.shared.record(DownloadHistoryItem(
                name: item.analysis.name, date: .now, status: .cancelled, driveLink: item.driveLink
            ))
        case .ready, .downloading, .paused:
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
        guard item.analysis.type == .folder,
              let destinationURL = item.destinationURL ?? selectedDestinationURL else { return }
        GoogleDriveDownloadService.removePartialFolderArtifact(itemID: item.itemID, in: destinationURL)
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

    func resumeQueue() {
        guard isQueuePaused else { return }
        isQueuePaused = false
        processQueueIfNeeded()
    }

    /// Retries only this item; the rest of the queue's order and state are untouched.
    func retryQueueItem(_ id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }), queue[index].status == .failed else { return }
        queue[index].status = .ready
        queue[index].errorMessage = nil
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
    }

    func clearCompletedQueueItems() {
        queue.removeAll { $0.status == .completed }
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
        showRestorePrompt = true
    }

    /// A queue item that was mid-download when the app last quit never finished;
    /// it's restored as ready so the engine can pick it back up from scratch.
    func restoreSavedQueue() {
        guard var saved = pendingRestoreQueue else { return }
        for index in saved.indices where saved[index].status == .downloading {
            saved[index].status = .ready
        }
        queue = saved
        pendingRestoreQueue = nil
        showRestorePrompt = false
        QueueStore.save(queue)
    }

    func discardSavedQueue() {
        pendingRestoreQueue = nil
        showRestorePrompt = false
        QueueStore.clear()
    }

    private static func friendlyMessage(for error: Error) -> String {
        if let driveError = error as? DriveDownloadError {
            switch driveError {
            case .server(let statusCode, _):
                switch statusCode {
                case 404:
                    return "This link doesn't point to an existing Google Drive file or folder."
                case 403:
                    return "You don't have permission to access this item."
                default:
                    return "Google Drive couldn't process this link right now."
                }
            case .invalidResponse, .unsupportedFileType:
                return driveError.errorDescription ?? "Google Drive couldn't process this link right now."
            }
        }

        if error is URLError {
            return "Check your internet connection and try again."
        }

        return "Something went wrong. Please try again."
    }
}

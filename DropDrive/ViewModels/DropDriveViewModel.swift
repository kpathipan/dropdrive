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

    var linkAnalysisState: LinkAnalysisState = .idle

    var queue: [QueueItem] = []
    var activeQueueItemID: UUID?
    var activeProgress: DownloadProgress?
    var highlightedQueueItemID: UUID?
    var showLargeDownloadWarning = false

    var pendingRestoreQueue: [QueueItem]?
    var showRestorePrompt = false

    private let loginManager: LoginManaging
    private let downloadService: DownloadServicing
    private let folderSelectionService: FolderSelectionServicing
    private var downloadTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var highlightTask: Task<Void, Never>?

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
            let result = try await downloadService.analyzeLink(itemID: itemID)
            guard !Task.isCancelled else { return }

            switch result {
            case .success(let analysis):
                handleSuccessfulAnalysis(analysis, trimmedLink: trimmedLink)
            case .needsAuthentication:
                linkAnalysisState = .needsConnection
            }
        } catch {
            guard !Task.isCancelled else { return }
            linkAnalysisState = .failed(Self.friendlyMessage(for: error))
        }
    }

    /// Each successful analysis becomes one queue item, unless its Drive item ID is
    /// already in the queue: a still-active duplicate is highlighted and rejected, a
    /// completed one asks whether to queue a fresh copy.
    private func handleSuccessfulAnalysis(_ analysis: DriveLinkAnalysis, trimmedLink: String) {
        if let existing = queue.first(where: { $0.itemID == analysis.itemID }) {
            if existing.status == .completed {
                linkAnalysisState = .duplicateCompleted(analysis)
            } else {
                linkAnalysisState = .duplicateActive
                flashDuplicate(itemID: analysis.itemID)
                driveLink = ""
            }
            return
        }

        enqueue(analysis: analysis, driveLink: trimmedLink)
        driveLink = ""
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

    /// Bypasses the debounce for an immediate confirm action (Return key).
    func handleSubmit() {
        let trimmed = driveLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        analysisTask?.cancel()
        analysisTask = Task {
            await runAnalysis(for: trimmed)
        }
    }

    // MARK: - Queue

    private func enqueue(analysis: DriveLinkAnalysis, driveLink: String) {
        queue.append(QueueItem(driveLink: driveLink, analysis: analysis))
        QueueStore.save(queue)
    }

    func startQueueDownloads() {
        guard canStartQueue else { return }
        if isLargeDownload {
            showLargeDownloadWarning = true
        } else {
            processQueueIfNeeded()
        }
    }

    func confirmLargeDownloadAndStart() {
        showLargeDownloadWarning = false
        processQueueIfNeeded()
    }

    func cancelLargeDownloadWarning() {
        showLargeDownloadWarning = false
    }

    private func processQueueIfNeeded() {
        guard activeQueueItemID == nil else { return }
        guard let destinationURL = selectedDestinationURL else { return }
        guard let index = queue.firstIndex(where: { $0.status == .ready }) else { return }
        startDownloading(queue[index], destinationURL: destinationURL)
    }

    private func startDownloading(_ item: QueueItem, destinationURL: URL) {
        guard let index = queue.firstIndex(where: { $0.id == item.id }) else { return }
        queue[index].status = .downloading
        activeQueueItemID = item.id
        activeProgress = DownloadProgress(currentFileName: "Preparing…")
        QueueStore.save(queue)

        let request = DownloadRequest(driveLink: item.driveLink, itemID: item.itemID, destinationURL: destinationURL)

        downloadTask = Task {
            do {
                let resultURL = try await downloadService.download(request) { progress in
                    Task { @MainActor [self] in
                        self.activeProgress = progress
                    }
                }
                try Task.checkCancellation()
                finishActiveItem(item.id, status: .completed, resultURL: resultURL, errorMessage: nil)
            } catch is CancellationError {
                finishActiveItem(item.id, status: .cancelled, resultURL: nil, errorMessage: nil)
            } catch {
                finishActiveItem(item.id, status: .failed, resultURL: nil, errorMessage: Self.friendlyMessage(for: error))
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
                driveLink: item.driveLink
            ))
        case .failed:
            DownloadHistoryStore.shared.record(DownloadHistoryItem(
                name: item.analysis.name, date: .now, status: .failed, driveLink: item.driveLink
            ))
        case .cancelled:
            DownloadHistoryStore.shared.record(DownloadHistoryItem(
                name: item.analysis.name, date: .now, status: .cancelled, driveLink: item.driveLink
            ))
        case .ready, .downloading:
            break
        }

        processQueueIfNeeded()
    }

    func cancelActiveDownload() {
        downloadTask?.cancel()
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
        queue.removeAll { $0.id == id }
        QueueStore.save(queue)
    }

    func clearCompletedQueueItems() {
        queue.removeAll { $0.status == .completed }
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

import Foundation
import Observation

enum DownloadPhase: Equatable {
    case idle
    case downloading
    case success(folderURL: URL, fileCount: Int)
    case failed(message: String)
    case cancelled

    var isActive: Bool { self == .downloading }
}

@MainActor
@Observable
final class DropDriveViewModel {
    var driveLink = "" {
        didSet {
            guard driveLink != oldValue else { return }
            scheduleAnalysis()
        }
    }
    var selectedDestinationURL: URL?
    var googleAccount: GoogleAccount?
    var isSigningIn = false

    var downloadPhase: DownloadPhase = .idle
    var downloadProgress: DownloadProgress?
    var linkAnalysisState: LinkAnalysisState = .idle

    private let loginManager: LoginManaging
    private let downloadService: DownloadServicing
    private let folderSelectionService: FolderSelectionServicing
    private var downloadTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?

    init() {
        let loginManager = LoginManager.shared
        self.loginManager = loginManager
        self.downloadService = GoogleDriveDownloadService(loginManager: loginManager)
        self.folderSelectionService = FolderSelectionService()
        self.selectedDestinationURL = DestinationStore.restore()
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

    var canDownload: Bool {
        guard case .ready = linkAnalysisState else { return false }
        return selectedDestinationURL != nil && !downloadPhase.isActive && !isSigningIn
    }

    var isFormLocked: Bool {
        downloadPhase.isActive
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
                linkAnalysisState = .ready(analysis)
            case .needsAuthentication:
                linkAnalysisState = .needsConnection
            }
        } catch {
            guard !Task.isCancelled else { return }
            linkAnalysisState = .failed(Self.friendlyMessage(for: error))
        }
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        linkAnalysisState = .idle
        driveLink = ""
    }

    func retryAnalysis() {
        scheduleAnalysis()
    }

    /// Bypasses the debounce for an immediate confirm action (Return key): downloads
    /// right away if analysis is already ready, otherwise runs analysis immediately.
    func handleSubmit() {
        if canDownload {
            download()
            return
        }

        let trimmed = driveLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        analysisTask?.cancel()
        analysisTask = Task {
            await runAnalysis(for: trimmed)
        }
    }

    // MARK: - Download

    func download() {
        guard let destinationURL = selectedDestinationURL,
              let itemID = GoogleDriveLinkParser.itemID(from: driveLink) else {
            return
        }

        let request = DownloadRequest(itemID: itemID, destinationURL: destinationURL)

        downloadPhase = .downloading
        downloadProgress = DownloadProgress(currentFileName: "Preparing…")

        downloadTask = Task {
            do {
                let resultURL = try await downloadService.download(request) { progress in
                    Task { @MainActor [self] in
                        self.downloadProgress = progress
                    }
                }

                if Task.isCancelled {
                    downloadPhase = .cancelled
                } else {
                    downloadPhase = .success(folderURL: resultURL, fileCount: downloadProgress?.totalFiles ?? 0)
                    NotificationService.notifyDownloadComplete(name: resultURL.lastPathComponent, folderURL: resultURL)
                }
            } catch is CancellationError {
                downloadPhase = .cancelled
            } catch {
                downloadPhase = Task.isCancelled ? .cancelled : .failed(message: Self.friendlyMessage(for: error))
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func retryDownload() {
        downloadPhase = .idle
        downloadProgress = nil
        download()
    }

    /// Used by every dismiss-style action (Download Another, error/cancelled dismiss):
    /// clears the current link/analysis so the form is ready for a fresh paste. The
    /// destination folder is intentionally kept.
    func dismissDownloadResult() {
        downloadPhase = .idle
        downloadProgress = nil
        driveLink = ""
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

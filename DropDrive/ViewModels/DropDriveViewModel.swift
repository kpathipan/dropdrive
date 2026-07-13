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
    var statusMessage = "Sign in, paste a Drive link, and choose where it should land."
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

    var isGoogleSignedIn: Bool {
        googleAccount != nil
    }

    var destinationDisplayName: String {
        selectedDestinationURL?.path(percentEncoded: false) ?? "No folder selected"
    }

    var canDownload: Bool {
        guard case .ready = linkAnalysisState else { return false }
        return selectedDestinationURL != nil && !downloadPhase.isActive && !isSigningIn
    }

    var isFormLocked: Bool {
        downloadPhase.isActive
    }

    var footerStatusText: String {
        switch downloadPhase {
        case .idle:
            isGoogleSignedIn ? "Ready" : "Not connected"
        case .downloading:
            "Downloading…"
        case .success:
            "Completed"
        case .failed:
            "Failed"
        case .cancelled:
            "Cancelled"
        }
    }

    func restoreLogin() {
        Task {
            googleAccount = await loginManager.restoreSavedAccount()
            statusMessage = googleAccount == nil ? "Connect Google Drive to continue." : "Google Drive connected."
        }
    }

    func signInWithGoogle() {
        Task {
            isSigningIn = true
            statusMessage = "Opening Google sign-in…"
            defer { isSigningIn = false }

            do {
                let account = try await loginManager.signIn()
                googleAccount = account
                statusMessage = "Google Drive connected."
                scheduleAnalysis()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func signOut() {
        loginManager.signOut()
        googleAccount = nil
        statusMessage = "Signed out of Google Drive."
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
            statusMessage = "Destination folder selected."
        }
    }

    // MARK: - Link analysis

    private func scheduleAnalysis() {
        analysisTask?.cancel()
        linkAnalysisState = .idle

        guard let itemID = GoogleDriveLinkParser.itemID(from: driveLink) else {
            return
        }

        analysisTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await performAnalysis(itemID: itemID)
        }
    }

    private func performAnalysis(itemID: String) async {
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
            linkAnalysisState = .failed(error.localizedDescription)
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

    // MARK: - Download

    func download() {
        guard let destinationURL = selectedDestinationURL else {
            statusMessage = "Choose a destination folder before downloading."
            return
        }

        guard let itemID = GoogleDriveLinkParser.itemID(from: driveLink) else {
            statusMessage = "Paste a valid Google Drive link."
            return
        }

        let request = DownloadRequest(
            driveLink: driveLink.trimmingCharacters(in: .whitespacesAndNewlines),
            itemID: itemID,
            destinationURL: destinationURL
        )

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
                }
            } catch is CancellationError {
                downloadPhase = .cancelled
            } catch {
                downloadPhase = Task.isCancelled ? .cancelled : .failed(message: error.localizedDescription)
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

    func dismissDownloadResult() {
        downloadPhase = .idle
        downloadProgress = nil
        scheduleAnalysis()
    }
}

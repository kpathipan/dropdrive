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
    var driveLink = ""
    var selectedDestinationURL: URL?
    var statusMessage = "Sign in, paste a Drive folder link, and choose where it should land."
    var googleAccount: GoogleAccount?
    var isSigningIn = false

    var downloadPhase: DownloadPhase = .idle
    var downloadProgress: DownloadProgress?

    private let loginManager: LoginManaging
    private let downloadService: DownloadServicing
    private let folderSelectionService: FolderSelectionServicing
    private var downloadTask: Task<Void, Never>?

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
        GoogleDriveLinkParser.folderID(from: driveLink) != nil
            && selectedDestinationURL != nil
            && !downloadPhase.isActive
            && !isSigningIn
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

    func download() {
        guard let destinationURL = selectedDestinationURL else {
            statusMessage = "Choose a destination folder before downloading."
            return
        }

        guard let folderID = GoogleDriveLinkParser.folderID(from: driveLink) else {
            statusMessage = "Paste a valid Google Drive folder link."
            return
        }

        let request = DownloadRequest(
            driveLink: driveLink.trimmingCharacters(in: .whitespacesAndNewlines),
            folderID: folderID,
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
    }
}

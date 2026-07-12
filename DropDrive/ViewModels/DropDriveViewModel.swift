import Foundation
import Observation

@MainActor
@Observable
final class DropDriveViewModel {
    var driveLink = ""
    var selectedDestinationURL: URL?
    var statusMessage = "Sign in, paste a Drive folder link, and choose where it should land."
    var googleAccount: GoogleAccount?
    var isWorking = false

    private let loginManager: LoginManaging
    private let downloadService: DownloadServicing
    private let folderSelectionService: FolderSelectionServicing

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
        GoogleDriveLinkParser.folderID(from: driveLink) != nil && selectedDestinationURL != nil && !isWorking
    }

    func restoreLogin() {
        Task {
            googleAccount = await loginManager.restoreSavedAccount()
            statusMessage = googleAccount == nil ? "Connect Google Drive to continue." : "Google Drive connected."
        }
    }

    func signInWithGoogle() {
        Task {
            await performWork(startMessage: "Opening Google sign-in...") {
                let account = try await self.loginManager.signIn()
                self.googleAccount = account
                self.statusMessage = "Google Drive connected."
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
        Task {
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

            await performWork(startMessage: "Preparing download...") {
                try await self.downloadService.download(request) { message in
                    Task { @MainActor [self] in
                        self.statusMessage = message
                    }
                }
            }
        }
    }

    private func performWork(startMessage: String, operation: @escaping () async throws -> Void) async {
        isWorking = true
        statusMessage = startMessage
        defer { isWorking = false }

        do {
            try await operation()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

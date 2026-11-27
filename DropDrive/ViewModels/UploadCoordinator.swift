import AppKit
import Foundation
import Observation

@MainActor @Observable
final class UploadCoordinator {
    static let shared = UploadCoordinator()
    private(set) var jobs: [AutomationJob] = []
    private(set) var storageError: String?
    var selectedFolder: UploadFolder?
    var selectedAccountID: String?
    var selectedFiles: [URL] = []
    var selectedNames: [String: String] = [:]
    var hasUploadPermission = false
    var folderInput = ""
    var folders: [UploadFolder] = []
    var nextFolderPage: String?
    var isLoadingFolders = false
    var isAuthorizing = false
    var isCreatingFolder = false
    var message: String?
    @ObservationIgnored private let engine: DriveUploadEngine
    @ObservationIgnored private let store: UploadStore
    @ObservationIgnored private var records: [UUID: PrivateUploadRecord] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var bookmarks: [String: Data] = [:]
    @ObservationIgnored private var lastProgressAt: Date = .distantPast
    @ObservationIgnored private var folderSelectionRevision = 0

    init(engine: DriveUploadEngine = DriveUploadEngine(), store: UploadStore? = nil) {
        let store = store ?? UploadStore()
        self.engine = engine; self.store = store
        do {
            records = try store.load()
            for id in Array(records.keys) {
                if var record = records[id], !record.job.terminal {
                    record.job.state = "interrupted"
                    record.job.message = "Upload paused after the app closed. Retry this job to resume with its original file ID."
                    try store.save(record); records[id] = record
                }
            }
            refreshJobs()
        } catch { storageError = "Upload checkpoints could not be loaded safely. Uploads are disabled; existing checkpoints were preserved." }
        if let data = UserDefaults.standard.data(forKey: "upload.selectedFolder.v1"),
           let folder = try? JSONDecoder().decode(UploadFolder.self, from: data) {
            selectedFolder = folder; selectedAccountID = folder.accountID; folderInput = folder.id
        }
    }

    private func refreshJobs() { jobs = records.values.map(\.job).sorted { $0.updatedAt > $1.updatedAt } }
    var hasActiveJobs: Bool { jobs.contains { !$0.terminal } }
    private func checkpoint(_ record: PrivateUploadRecord) throws {
        var saved = record; saved.job.updatedAt = .now
        do { try store.save(saved) }
        catch {
            storageError = "Could not durably save upload progress. Check local disk space and reopen DropDrive; existing checkpoints and files were preserved."
            saved.job.state = "failed"; saved.job.errorCode = "checkpoint_failed"; saved.job.message = storageError
            records[saved.job.command.id] = saved; refreshJobs()
            throw AutomationFailure("checkpoint_failed", storageError!)
        }
        records[saved.job.command.id] = saved; refreshJobs()
    }

    func job(_ id: UUID) -> AutomationJob? { records[id]?.job }

    /// Finished rows only. "interrupted" stays: it holds the resumable session.
    static let clearableStates: Set<String> = ["completed", "cancelled", "failed"]
    var hasClearableJobs: Bool { jobs.contains { Self.clearableStates.contains($0.state) } }

    func clearHistory() {
        for (id, record) in records where tasks[id] == nil && Self.clearableStates.contains(record.job.state) {
            do { try store.delete(id); records[id] = nil }
            catch { message = tr("Some upload history could not be cleared.", "ล้างประวัติอัปโหลดบางรายการไม่ได้") }
        }
        refreshJobs()
    }

    func submit(_ command: AutomationCommand, bookmark: Data? = nil) throws -> AutomationJob {
        try command.validate()
        guard storageError == nil else { throw AutomationFailure("unsafe_checkpoint", storageError!) }
        if let existing = records[command.id] {
            guard existing.job.command == command else { throw AutomationFailure("id_conflict", "This request ID belongs to a different upload command.") }
            return existing.job
        }
        guard records.count < 1000 else { throw AutomationFailure("ledger_full", "Upload ledger is full. Existing request IDs were preserved.") }
        guard records.values.filter({ !$0.job.terminal }).count < 100 else { throw AutomationFailure("queue_full", "Upload queue is full.") }
        let account = try LoginManager.shared.uploadAccountID(preferred: command.accountID)
        let name = command.name ?? command.sourcePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        try UploadInput.validateName(name)
        let identity: UploadSourceIdentity?
        if command.action == "upload" {
            let url = URL(fileURLWithPath: command.sourcePath!)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            identity = try UploadSource(path: command.sourcePath!).identity
        } else { identity = nil }
        let folder = try UploadInput.folderID(command.driveFolder ?? "root")
        if records.values.contains(where: { record in
            !record.job.terminal && record.accountID == account && record.effectiveName == name
                && (try? UploadInput.folderID(record.job.command.driveFolder ?? "root")) == folder
        }) { throw AutomationFailure("duplicate_active", "This filename already has a pending upload to that folder. Inspect or cancel the original job.") }
        let job = AutomationJob(command: command, state: "queued", name: name, fileCount: 1,
                                totalBytes: identity?.size, upload: UploadStatus(totalBytes: identity?.size ?? 0))
        try checkpoint(PrivateUploadRecord(job: job, effectiveName: name, accountID: account,
            sourceIdentity: identity, sourceBookmark: bookmark))
        startNext()
        return records[command.id]!.job
    }

    private func startNext() {
        guard storageError == nil, tasks.isEmpty, let next = records.values.filter({ $0.job.state == "queued" }).min(by: { $0.job.updatedAt < $1.job.updatedAt }) else { return }
        let id = next.job.command.id
        tasks[id] = Task { @MainActor in
            defer { self.tasks[id] = nil; self.startNext() }
            var scopedURL: URL?
            if let data = next.sourceBookmark {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale),
                   url.path == next.job.command.sourcePath, url.startAccessingSecurityScopedResource() { scopedURL = url }
            }
            defer { scopedURL?.stopAccessingSecurityScopedResource() }
            do {
                if next.job.command.action == "upload_create_folder" {
                    var record = next
                    record.job.state = "preparing"; try self.checkpoint(record)
                    if record.fileID == nil {
                        record.fileID = try await self.engine.generatedID(account: record.accountID)
                        try self.checkpoint(record)
                    }
                    let folder = try await self.engine.createFolder(id: record.fileID!, name: record.effectiveName,
                        parent: record.job.command.driveFolder ?? "root", account: record.accountID)
                    record.job.state = "completed"
                    record.job.upload = UploadStatus(remoteFileID: folder.id, remoteURL: "https://drive.google.com/drive/folders/\(folder.id)", verified: true, folder: folder)
                    try self.checkpoint(record)
                } else {
                    _ = try await self.engine.run(next, checkpoint: { record in
                        try await self.checkpoint(record)
                    }, progress: { bytes in await self.progress(id, bytes: bytes) })
                }
            } catch {
                guard var record = self.records[id] else { return }
                if Task.isCancelled || error is CancellationError {
                    // The last PUT may already have completed on Drive. Confirm
                    // outside the cancelled task before declaring cancellation.
                    if record.fileID != nil, record.sourceMD5 != nil {
                        let verification = Task.detached { try await self.engine.verify(record) }
                        if let remote = try? await verification.value {
                            record.job.state = "completed"; record.job.upload?.verified = true
                            record.job.upload?.remoteFileID = remote.id; record.job.upload?.md5Checksum = remote.md5Checksum
                            record.job.upload?.remoteURL = "https://drive.google.com/file/d/\(remote.id)/view"
                            record.job.upload?.bytesUploaded = record.sourceIdentity?.size ?? 0
                            record.sessionURL = nil; record.job.message = nil
                            try? self.checkpoint(record); return
                        }
                    }
                    record.job.state = "cancelled"; record.job.errorCode = "cancelled"
                    record.job.message = "Upload stopped. Existing local and Drive files were preserved; retry uses the same file ID."
                } else {
                    let failure = error as? AutomationFailure ?? AutomationFailure("upload_failed", "Upload failed. Retry this job; credentials and session details are kept inside DropDrive.")
                    record.job.state = "failed"; record.job.errorCode = failure.code; record.job.message = failure.message
                }
                record.job.upload?.nextRetryAt = nil
                try? self.checkpoint(record)
            }
        }
    }

    private func progress(_ id: UUID, bytes: Int64) {
        guard var record = records[id], record.job.state == "uploading" else { return }
        guard Date.now.timeIntervalSince(lastProgressAt) >= 0.15 || bytes == record.job.upload?.totalBytes else { return }
        lastProgressAt = .now
        record.job.upload?.bytesUploaded = bytes
        records[id] = record; refreshJobs() // Progress is transient; chunk ACKs are durable.
    }

    func cancel(_ id: UUID) throws -> AutomationJob {
        guard var record = records[id] else { throw AutomationFailure("unknown_job", "No upload with this job ID.") }
        if record.job.state == "completed" { return record.job }
        if let task = tasks[id] {
            record.job.state = "cancelling"; try checkpoint(record); task.cancel()
        } else {
            record.job.state = "cancelled"; record.job.errorCode = "cancelled"
            record.job.message = "Cancelled before upload. Local and Drive files were preserved."
            try checkpoint(record)
        }
        return records[id]!.job
    }

    func retry(_ id: UUID, newName: String?) throws -> AutomationJob {
        guard var record = records[id] else { throw AutomationFailure("unknown_job", "No upload with this job ID.") }
        guard tasks[id] == nil else { return record.job }
        guard ["failed", "cancelled", "interrupted"].contains(record.job.state) else { return record.job }
        if let newName, newName != record.effectiveName {
            try UploadInput.validateName(newName)
            guard record.job.errorCode == "name_conflict", record.sessionURL == nil, record.confirmedOffset == 0 else {
                throw AutomationFailure("rename_not_safe", "A started upload cannot be renamed during retry. Cancel it and submit a separate job if needed.")
            }
            record.effectiveName = newName; record.job.name = newName
        }
        record.job.state = "queued"; record.job.errorCode = nil; record.job.message = nil
        try checkpoint(record); startNext(); return records[id]!.job
    }

    func verify(_ id: UUID) async throws -> AutomationJob {
        guard var record = records[id] else { throw AutomationFailure("unknown_job", "No upload with this job ID.") }
        guard tasks[id] == nil else { throw AutomationFailure("upload_in_progress", "Wait until this upload stops before independently verifying it.") }
        guard record.job.command.action == "upload" else { return record.job }
        let remote = try await engine.verify(record)
        record.job.state = "completed"; record.job.errorCode = nil; record.job.message = nil
        record.job.upload?.verified = true; record.job.upload?.remoteFileID = remote.id
        record.job.upload?.remoteURL = "https://drive.google.com/file/d/\(remote.id)/view"
        record.job.upload?.md5Checksum = remote.md5Checksum
        record.job.upload?.bytesUploaded = record.sourceIdentity?.size ?? 0; record.sessionURL = nil
        try checkpoint(record); return record.job
    }

    func resolveFolder(_ input: String, accountID: String?) async throws -> UploadFolder {
        let account = try LoginManager.shared.uploadAccountID(preferred: accountID)
        return try await engine.folder(input, account: account)
    }

    func listFolders(parent: String?, pageToken: String?, accountID: String?) async throws -> UploadFolderPage {
        let account = try LoginManager.shared.uploadAccountID(preferred: accountID)
        return try await engine.folders(parent: try parent.map(UploadInput.folderID), pageToken: pageToken, account: account)
    }

    func selectFiles(_ urls: [URL]) {
        for url in urls where !selectedFiles.contains(where: { $0.path == url.path }) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                _ = try UploadSource(path: url.path)
                selectedFiles.append(url)
                bookmarks[url.path] = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            } catch { message = (error as? AutomationFailure)?.message ?? "Could not read the selected file." }
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true; panel.resolvesAliases = false
        let controller = StatusItemController.current
        let restore = controller?.hidePopoverForExternalPanel() ?? false
        panel.begin { response in
            Task { @MainActor in
                if response == .OK { self.selectFiles(panel.urls) }
                controller?.restorePopoverAfterExternalPanel(if: restore)
            }
        }
    }

    func useFolder(_ input: String) async {
        folderSelectionRevision += 1
        let revision = folderSelectionRevision, requestedAccount = selectedAccountID
        isLoadingFolders = true
        defer { if revision == folderSelectionRevision { isLoadingFolders = false } }
        do {
            let folder = try await resolveFolder(input, accountID: requestedAccount)
            guard revision == folderSelectionRevision, selectedAccountID == requestedAccount else { return }
            guard folder.canUpload else { throw AutomationFailure("folder_read_only", "This account cannot add files to this folder.") }
            selectedFolder = folder; selectedAccountID = folder.accountID; folderInput = folder.id
            UserDefaults.standard.set(try JSONEncoder().encode(folder), forKey: "upload.selectedFolder.v1")
            message = nil
        } catch {
            if revision == folderSelectionRevision { message = (error as? AutomationFailure)?.message ?? "Could not resolve the folder." }
        }
    }

    func browseFolders(more: Bool = false) async {
        isLoadingFolders = true; defer { isLoadingFolders = false }
        do {
            let page = try await listFolders(parent: nil, pageToken: more ? nextFolderPage : nil, accountID: selectedAccountID)
            folders = more ? folders + page.folders : page.folders; nextFolderPage = page.nextPageToken; message = nil
        } catch { message = (error as? AutomationFailure)?.message ?? "Could not list folders." }
    }

    func authorize() async {
        isAuthorizing = true; defer { isAuthorizing = false }
        do {
            _ = try await LoginManager.shared.authorizeUploads(accountID: selectedAccountID)
            DropDriveViewModel.shared.restoreLogin()
            selectedAccountID = try LoginManager.shared.uploadAccountID(preferred: selectedAccountID)
            hasUploadPermission = true; message = nil; await browseFolders()
        } catch { message = (error as? AutomationFailure)?.message ?? "Upload permission was not granted. Try again from Enable uploads." }
    }

    func checkPermission() async {
        let requestedAccount = selectedAccountID
        do {
            let account = try LoginManager.shared.uploadAccountID(preferred: requestedAccount)
            _ = try await LoginManager.shared.uploadAccessToken(accountID: account)
            guard selectedAccountID == requestedAccount else { return }
            selectedAccountID = account; hasUploadPermission = true
        } catch { if selectedAccountID == requestedAccount { hasUploadPermission = false } }
    }

    func startSelectedFiles() {
        guard let folder = selectedFolder, folder.accountID == selectedAccountID else {
            message = "Choose and confirm a Drive destination for this account first."; return
        }
        var accepted: Set<String> = []
        for file in selectedFiles {
            do {
                let command = AutomationCommand(id: UUID(), action: "upload", name: selectedNames[file.path] ?? file.lastPathComponent,
                    sourcePath: file.path, driveFolder: folder.id, accountID: folder.accountID)
                _ = try submit(command, bookmark: bookmarks[file.path]); accepted.insert(file.path)
            } catch { message = (error as? AutomationFailure)?.message ?? "Could not queue this upload." }
        }
        selectedFiles.removeAll { accepted.contains($0.path) }
    }

    func createDestination(named name: String) async {
        guard !isCreatingFolder else { return }
        isCreatingFolder = true; defer { isCreatingFolder = false }
        do {
            let command = AutomationCommand(id: UUID(), action: "upload_create_folder", name: name,
                driveFolder: selectedFolder?.id ?? "root", accountID: selectedAccountID)
            let accepted = try submit(command)
            while let current = job(accepted.command.id), !current.terminal { try await Task.sleep(for: .milliseconds(250)) }
            guard let done = job(accepted.command.id), done.state == "completed", let folder = done.upload?.folder else {
                throw AutomationFailure("folder_create_failed", job(accepted.command.id)?.message ?? "Folder could not be created.")
            }
            await useFolder(folder.id)
        } catch { message = (error as? AutomationFailure)?.message ?? "Could not create the folder." }
    }
}

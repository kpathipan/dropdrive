import Foundation
import Darwin

/// Private, same-user IPC. No TCP listener, web endpoint, OAuth token or shell command.
/// A client atomically deposits a JSON request; the app uses its existing engine.
@MainActor
final class AutomationBridge {
    static let shared = AutomationBridge()
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DropDrive/Automation/v1", isDirectory: true)
    private let fm = FileManager.default
    private var timer: Timer?
    private var jobs: [UUID: AutomationJob] = [:]
    private var operations: [UUID: Task<Void, Never>] = [:]
    private var started = false
    private var inbox: URL { Self.directory.appendingPathComponent("requests") }
    private var replies: URL { Self.directory.appendingPathComponent("replies") }
    private var ledger: URL { Self.directory.appendingPathComponent("jobs") }

    func start() {
        guard !started else { return }
        // Explicitly enabled by the local MCP installer, never by a web URL.
        guard fm.fileExists(atPath: Self.directory.appendingPathComponent("enabled").path) else { return }
        do {
            for path in [Self.directory, inbox, replies, ledger] { try prepareDirectory(path) }
            for path in try fm.contentsOfDirectory(at: ledger, includingPropertiesForKeys: nil) where path.pathExtension == "json" {
                guard let data = try? secureRead(path), let job = try? JSONDecoder().decode(AutomationJob.self, from: data) else { continue }
                guard path.deletingPathExtension().lastPathComponent == job.command.id.uuidString else { continue }
                jobs[job.command.id] = job
            }
            started = true
            let model = DropDriveViewModel.shared
            for (id, var job) in jobs where !job.terminal {
                if let item = (model.queue + (model.pendingRestoreQueue ?? [])).first(where: { $0.id == id }) {
                    update(item, awaitingRestore: model.pendingRestoreQueue?.contains(where: { $0.id == id }) == true)
                } else {
                    // Never reissue a download after an uncertain app exit.
                    job.state = "interrupted"; job.errorCode = "app_restarted"
                    job.message = "App restarted before a queue checkpoint. Inspect existing files before submitting a new job."
                    try save(job)
                }
            }
            try write(["protocolVersion": "1", "pid": String(getpid())], to: Self.directory.appendingPathComponent("endpoint.json"))
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                Task { @MainActor in self.drain() }
            }
            drain()
        } catch {
            started = false
            NSLog("DropDrive automation unavailable: %@", error.localizedDescription)
        }
    }

    private func prepareDirectory(_ path: URL) throws {
        if !fm.fileExists(atPath: path.path) {
            try fm.createDirectory(at: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let attributes = try fm.attributesOfItem(atPath: path.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077 == 0 else {
            throw AutomationFailure("unsafe_permissions", "Automation directories must be owned by this user and mode 0700.")
        }
    }

    private func secureRead(_ path: URL) throws -> Data {
        let fd = Darwin.open(path.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw AutomationFailure("invalid_file", "Cannot open request safely.") }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw AutomationFailure("invalid_file", "Cannot inspect request.") }
        // Client uses link/unlink for an atomic, no-clobber publish. Defer the
        // tiny two-link window rather than deleting a still-publishing request.
        if info.st_nlink > 1 { throw AutomationFailure("writing_request", "Request is still being published.") }
        guard (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1, info.st_size <= 65_536,
              info.st_mode & 0o077 == 0 else { throw AutomationFailure("invalid_file", "Unsafe request file.") }
        return try FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd() ?? Data()
    }

    private func write<T: Encodable>(_ value: T, to path: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: path, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }

    private func save(_ job: AutomationJob) throws {
        var updated = job; updated.updatedAt = .now
        try write(updated, to: ledger.appendingPathComponent(updated.command.id.uuidString + ".json"))
        jobs[updated.command.id] = updated
    }

    func update(_ item: QueueItem, awaitingRestore: Bool = false) {
        guard started, var job = jobs[item.id] else { return }
        let state = awaitingRestore ? "awaiting_restore" : (item.status == .ready ? "queued" : item.status.rawValue)
        let message = awaitingRestore ? "Open DropDrive and choose whether to restore the saved queue. No download was restarted by MCP." : item.errorMessage
        guard job.state != state || job.outputPath != item.resultURL?.path || job.message != message else { return }
        job.state = state; job.outputPath = item.resultURL?.path; job.message = message
        job.errorCode = item.attentionKind?.rawValue
        do { try save(job) } catch { NSLog("DropDrive automation checkpoint failed: %@", error.localizedDescription) }
    }

    func userRemoved(_ id: UUID) {
        guard started, var job = jobs[id], job.state != "completed" else { return }
        job.state = "cancelled"; job.errorCode = "removed_by_user"
        job.message = "The user removed this job or discarded its saved queue. MCP did not restart it."
        do { try save(job) } catch { NSLog("DropDrive automation cancellation checkpoint failed: %@", error.localizedDescription) }
    }

    private func drain() {
        guard started, let paths = try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else { return }
        for path in paths.filter({ $0.pathExtension == "json" }).prefix(32) {
            guard let id = UUID(uuidString: path.deletingPathExtension().lastPathComponent),
                  path.lastPathComponent == id.uuidString + ".json" else { continue }
            do {
                let command = try JSONDecoder().decode(AutomationCommand.self, from: secureRead(path))
                guard command.id == id else { throw AutomationFailure("invalid_request", "Request filename and ID differ.") }
                let reply = try receive(command)
                try write(reply, to: replies.appendingPathComponent(id.uuidString + ".json"))
            } catch {
                let failure = error as? AutomationFailure ?? AutomationFailure("invalid_request", "Could not process local command.")
                if failure.code == "writing_request" { continue }
                try? write(AutomationReply(id: id, ok: false, error: failure), to: replies.appendingPathComponent(id.uuidString + ".json"))
            }
            try? fm.removeItem(at: path)
        }
    }

    private func receive(_ command: AutomationCommand) throws -> AutomationReply {
        try command.validate()
        let model = DropDriveViewModel.shared
        if command.action == "ping" {
            return AutomationReply(id: command.id, appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, queuePaused: model.isQueuePaused)
        }
        if command.action == "status" {
            let id = command.jobID!
            if let item = (model.queue + (model.pendingRestoreQueue ?? [])).first(where: { $0.id == id }) {
                update(item, awaitingRestore: model.pendingRestoreQueue?.contains(where: { $0.id == id }) == true)
            }
            guard let job = jobs[id] else { throw AutomationFailure("unknown_job", "No automation job with this ID.") }
            let progress = model.activeQueueItemID == id ? model.activeProgress : nil
            return AutomationReply(id: command.id, job: job, queuePaused: model.isQueuePaused,
                                   bytesDownloaded: progress?.bytesDownloaded, completedFiles: progress?.completedFiles,
                                   bytesPerSecond: progress?.bytesPerSecond, percentage: progress?.activeDisplayPercentage)
        }
        if let existing = jobs[command.id] {
            guard existing.command == command else { throw AutomationFailure("id_conflict", "This request ID belongs to a different command.") }
            return AutomationReply(id: command.id, job: existing)
        }
        guard jobs.count < 1000 else { throw AutomationFailure("ledger_full", "Automation ledger is full. No download started.") }
        guard operations.count < 4 else { throw AutomationFailure("busy", "Four analyses are already running. Retry later with the same ID.") }
        let job = AutomationJob(command: command, state: "analyzing")
        try save(job) // Durable acceptance precedes side effects.
        operations[command.id] = Task { @MainActor in
            defer { self.operations[command.id] = nil }
            do {
                let finished = try await model.performAutomation(command)
                try self.save(finished)
                if command.action == "download" { model.startAutomationQueue() }
            } catch {
                var failed = self.jobs[command.id] ?? job
                let failure = error as? AutomationFailure ?? AutomationFailure("internal_error", "Command failed inside DropDrive.")
                failed.state = "failed"; failed.errorCode = failure.code; failed.message = failure.message
                try? self.save(failed)
            }
        }
        return AutomationReply(id: command.id, job: job)
    }
}

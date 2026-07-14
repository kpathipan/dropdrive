import Foundation

protocol DownloadServicing {
    @discardableResult
    func download(_ request: DownloadRequest, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL
    func analyzeLink(itemID: String, resourceKey: String?) async throws -> LinkAnalysisResult
    func clearAnalysisCache() async
}

struct DriveFile: Decodable {
    private struct Owner: Decodable {
        let displayName: String?
    }

    struct ShortcutDetails: Decodable {
        let targetId: String
        let targetMimeType: String?
        let targetResourceKey: String?
    }

    let id: String
    let name: String
    let mimeType: String
    let size: Int64?
    let ownerName: String?
    let shortcutDetails: ShortcutDetails?
    let resourceKey: String?

    var isFolder: Bool { mimeType == "application/vnd.google-apps.folder" }
    var isShortcut: Bool { mimeType == "application/vnd.google-apps.shortcut" }

    private enum CodingKeys: String, CodingKey {
        case id, name, mimeType, size, owners, shortcutDetails, resourceKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        if let sizeString = try container.decodeIfPresent(String.self, forKey: .size) {
            size = Int64(sizeString)
        } else {
            size = nil
        }
        let owners = try container.decodeIfPresent([Owner].self, forKey: .owners)
        ownerName = owners?.first?.displayName
        shortcutDetails = try container.decodeIfPresent(ShortcutDetails.self, forKey: .shortcutDetails)
        resourceKey = try container.decodeIfPresent(String.self, forKey: .resourceKey)
    }
}

private struct DriveListResponse: Decodable {
    let files: [DriveFile]
    let nextPageToken: String?
}

enum DriveDownloadError: LocalizedError {
    case invalidResponse
    case server(Int, String)
    case unsupportedFileType

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Received an unexpected response from Google Drive."
        case .server(let statusCode, let message):
            "Google Drive returned an error (\(statusCode)): \(message)"
        case .unsupportedFileType:
            "This file type can't be downloaded directly from Google Drive."
        }
    }
}

/// Thrown instead of a bare CancellationError when a download is interrupted (user
/// cancel/pause, or a network drop) with resume data available, so the caller can
/// persist it before the cancellation propagates upward as normal.
private struct DownloadInterruption: Error {
    let resumeData: Data?
}

/// Either an OAuth bearer token (private, user-authorized access) or a project API key
/// (anonymous access to publicly-shared files/folders, no sign-in required).
private enum DriveCredential: Sendable {
    case oauth(String)
    case apiKey(String)

    nonisolated func applying(to components: inout URLComponents) {
        if case .apiKey(let key) = self {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "key", value: key))
            components.queryItems = items
        }
    }

    nonisolated func applying(to request: inout URLRequest) {
        if case .oauth(let token) = self {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

/// In-memory cache of successful link analyses, keyed by item ID, shared across
/// service instances for the lifetime of the process. Avoids re-scanning the same
/// folder (which can involve many API calls) every time its link is re-analyzed.
private actor AnalysisCache {
    static let shared = AnalysisCache()

    private var storage: [String: LinkAnalysisResult] = [:]

    func get(_ key: String) -> LinkAnalysisResult? {
        storage[key]
    }

    func set(_ key: String, _ value: LinkAnalysisResult) {
        storage[key] = value
    }

    func clear() {
        storage.removeAll()
    }
}

/// Delegate-based downloads deliver `didWriteData` callbacks on URLSession's own
/// delegate queue — a different thread than whatever context `download()` itself
/// runs on — so this now needs real thread-safety, not just single-threaded
/// sequential access. Protected by a lock rather than an actor: its methods are
/// small, synchronous, and called from a non-async delegate callback, so making
/// them `async` would force a Task-per-callback right back into the hot path.
private final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var completedFiles: Int
    private let totalFiles: Int
    private var bytesDownloaded: Int64
    private let totalBytes: Int64
    private var lastSampleTime = Date()
    private var lastSampleBytes: Int64 = 0
    private var smoothedRate: Double = 0
    private var currentFileName = ""

    init(totalFiles: Int, totalBytes: Int64, completedFiles: Int = 0, bytesDownloaded: Int64 = 0) {
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
        self.completedFiles = completedFiles
        self.bytesDownloaded = bytesDownloaded
        self.lastSampleBytes = bytesDownloaded
    }

    func startingFile(_ name: String) -> DownloadProgress {
        lock.lock()
        defer { lock.unlock() }
        currentFileName = name
        return snapshot()
    }

    /// Byte counting always happens; the UI-facing snapshot is throttled to this
    /// same ~5Hz sampling window so a fast connection doesn't hop to the main
    /// actor thousands of times more often than any human could perceive.
    func addingBytes(_ count: Int64) -> DownloadProgress? {
        lock.lock()
        defer { lock.unlock() }
        bytesDownloaded += count
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSampleTime)
        guard elapsed >= 0.2 else { return nil }

        let deltaBytes = bytesDownloaded - lastSampleBytes
        let instantRate = elapsed > 0 ? Double(deltaBytes) / elapsed : 0
        smoothedRate = smoothedRate == 0 ? instantRate : (smoothedRate * 0.7 + instantRate * 0.3)
        lastSampleTime = now
        lastSampleBytes = bytesDownloaded
        return snapshot()
    }

    func completingFile() -> DownloadProgress {
        lock.lock()
        defer { lock.unlock() }
        completedFiles += 1
        return snapshot()
    }

    /// Callers already hold `lock`.
    private func snapshot() -> DownloadProgress {
        DownloadProgress(
            currentFileName: currentFileName,
            completedFiles: completedFiles,
            totalFiles: totalFiles,
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes,
            bytesPerSecond: smoothedRate
        )
    }
}

/// Bridges URLSessionDownloadTask's delegate callbacks into async/await. Progress
/// arrives in network-sized chunks as the OS receives them (typically tens of KB,
/// never one byte at a time), and the completed temp file is moved to its final
/// destination synchronously inside the delegate callback — required, since the
/// system deletes the temp file as soon as that method returns. Also used, one
/// instance per part, for multi-threaded ranged downloads.
private final class DownloadTaskCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destinationURL: URL
    private let onBytes: @Sendable (Int64) -> Void
    private let requireStatusCode: Int?

    private let stateLock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var task: URLSessionDownloadTask?
    private var didResume = false

    /// `requireStatusCode` is set to 206 for multi-part ranged downloads: a server
    /// that silently ignores the `Range` header (some CDNs do this inconsistently,
    /// especially once a URL is cached) responds 200 with the *entire* file instead
    /// of just the requested slice. Without this check that "part" file contains
    /// the whole file, and concatenating it with the other parts produces a
    /// corrupted, oversized result — silently, since 200 alone still looks like
    /// success. Failing this part throws, which sends the caller back to the
    /// single-stream fallback instead of writing a bad file.
    init(destinationURL: URL, onBytes: @escaping @Sendable (Int64) -> Void, requireStatusCode: Int? = nil) {
        self.destinationURL = destinationURL
        self.onBytes = onBytes
        self.requireStatusCode = requireStatusCode
    }

    func run(session: URLSession, request: URLRequest) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                stateLock.lock()
                self.continuation = continuation
                let task = session.downloadTask(with: request)
                self.task = task
                stateLock.unlock()
                task.resume()
            }
        } onCancel: { [weak self] in
            guard let self else { return }
            stateLock.lock()
            let task = self.task
            stateLock.unlock()
            task?.cancel { _ in }
        }
    }

    /// Resumes a previously-interrupted download using URLSession's own resume data,
    /// which encodes the byte offset, destination ETag/Last-Modified validators, etc.
    func resume(session: URLSession, resumeData: Data) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                stateLock.lock()
                self.continuation = continuation
                let task = session.downloadTask(withResumeData: resumeData)
                self.task = task
                stateLock.unlock()
                task.resume()
            }
        } onCancel: { [weak self] in
            guard let self else { return }
            stateLock.lock()
            let task = self.task
            stateLock.unlock()
            task?.cancel { _ in }
        }
    }

    private func complete(_ result: Result<URL, Error>) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !didResume else { return }
        didResume = true
        switch result {
        case .success(let url):
            continuation?.resume(returning: url)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        BandwidthLimiter.shared.throttle(bytes: bytesWritten)
        onBytes(bytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let http = downloadTask.response as? HTTPURLResponse else {
            complete(.failure(DriveDownloadError.invalidResponse))
            return
        }

        let isValidStatus = requireStatusCode.map { $0 == http.statusCode } ?? (200..<300).contains(http.statusCode)
        guard isValidStatus else {
            let data = try? Data(contentsOf: location)
            let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
            complete(.failure(DriveDownloadError.server(http.statusCode, message)))
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            complete(.success(destinationURL))
        } catch {
            complete(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let nsError = error as NSError
        let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data

        if resumeData != nil {
            complete(.failure(DownloadInterruption(resumeData: resumeData)))
        } else if nsError.code == NSURLErrorCancelled {
            complete(.failure(DownloadInterruption(resumeData: nil)))
        } else {
            complete(.failure(error))
        }
    }
}

struct GoogleDriveDownloadService: DownloadServicing {
    private static let apiBase = "https://www.googleapis.com/drive/v3/files"
    private static let metadataFields = "id,name,mimeType,size,owners(displayName),shortcutDetails(targetId,targetMimeType,targetResourceKey),resourceKey"
    private static let listFields = "nextPageToken, files(id, name, mimeType, size, shortcutDetails(targetId,targetMimeType,targetResourceKey), resourceKey)"

    /// Multi-part ranged downloads only pay off past this size; below it the extra
    /// round trips (probe + N connection setups) aren't worth it.
    private static let multiPartThresholdBytes: Int64 = 20 * 1024 * 1024
    private static let multiPartCount = 4

    private static let exportMimeTypes: [String: (mimeType: String, fileExtension: String)] = [
        "application/vnd.google-apps.document": ("application/vnd.openxmlformats-officedocument.wordprocessingml.document", "docx"),
        "application/vnd.google-apps.spreadsheet": ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xlsx"),
        "application/vnd.google-apps.presentation": ("application/vnd.openxmlformats-officedocument.presentationml.presentation", "pptx"),
        "application/vnd.google-apps.drawing": ("image/png", "png")
    ]

    private static var configuredAPIKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "GoogleAPIKey") as? String,
              !key.isEmpty, !key.contains("YOUR_") else {
            return nil
        }
        return key
    }

    private static func isDownloadable(mimeType: String) -> Bool {
        exportMimeTypes[mimeType] != nil || !mimeType.hasPrefix("application/vnd.google-apps.")
    }

    private let loginManager: LoginManaging
    private let urlSession: URLSession

    init(loginManager: LoginManaging, urlSession: URLSession = .shared) {
        self.loginManager = loginManager
        self.urlSession = urlSession
    }

    // MARK: - Link analysis

    func clearAnalysisCache() async {
        await AnalysisCache.shared.clear()
    }

    func analyzeLink(itemID: String, resourceKey: String?) async throws -> LinkAnalysisResult {
        if let cached = await AnalysisCache.shared.get(itemID) {
            return cached
        }

        let resourceKeys = resourceKey.map { [itemID: $0] } ?? [:]
        let result = try await performAnalysis(itemID: itemID, resourceKeys: resourceKeys)

        if case .success = result {
            await AnalysisCache.shared.set(itemID, result)
        }

        return result
    }

    private func performAnalysis(itemID: String, resourceKeys: [String: String]) async throws -> LinkAnalysisResult {
        if let apiKey = Self.configuredAPIKey,
           let metadata = try? await fetchMetadata(fileID: itemID, credential: .apiKey(apiKey), resourceKeys: resourceKeys) {
            let (resolved, updatedKeys) = try await resolvingShortcut(metadata, credential: .apiKey(apiKey), resourceKeys: resourceKeys)
            let analysis = try await buildAnalysis(for: resolved, credential: .apiKey(apiKey), resourceKeys: updatedKeys, isPublic: true)
            return .success(analysis)
        }

        guard let token = await loginManager.cachedAccessTokenIfAvailable() else {
            return .needsAuthentication
        }

        let metadata = try await fetchMetadata(fileID: itemID, credential: .oauth(token), resourceKeys: resourceKeys)
        let (resolved, updatedKeys) = try await resolvingShortcut(metadata, credential: .oauth(token), resourceKeys: resourceKeys)
        let analysis = try await buildAnalysis(for: resolved, credential: .oauth(token), resourceKeys: updatedKeys, isPublic: false)
        return .success(analysis)
    }

    private func buildAnalysis(
        for metadata: DriveFile,
        credential: DriveCredential,
        resourceKeys: [String: String],
        isPublic: Bool
    ) async throws -> DriveLinkAnalysis {
        guard metadata.isFolder else {
            return DriveLinkAnalysis(
                itemID: metadata.id,
                name: metadata.name,
                type: .file,
                isPublic: isPublic,
                requiresAuthentication: !isPublic,
                totalBytes: metadata.size,
                fileCount: nil,
                ownerName: metadata.ownerName,
                categoryBreakdown: nil
            )
        }

        let (fileCount, totalBytes, breakdown) = try await estimateFolderContents(folderID: metadata.id, credential: credential, resourceKeys: resourceKeys)
        return DriveLinkAnalysis(
            itemID: metadata.id,
            name: metadata.name,
            type: .folder,
            isPublic: isPublic,
            requiresAuthentication: !isPublic,
            totalBytes: totalBytes,
            fileCount: fileCount,
            ownerName: metadata.ownerName,
            categoryBreakdown: breakdown
        )
    }

    private func estimateFolderContents(
        folderID: String,
        credential: DriveCredential,
        resourceKeys: [String: String]
    ) async throws -> (fileCount: Int, totalBytes: Int64, breakdown: DriveLinkAnalysis.CategoryBreakdown) {
        try Task.checkCancellation()
        let children = try await listChildren(of: folderID, credential: credential, resourceKeys: resourceKeys)
        var count = 0
        var bytes: Int64 = 0
        var breakdown = DriveLinkAnalysis.CategoryBreakdown()

        for rawChild in children {
            let (child, updatedKeys) = try await resolvingShortcut(rawChild, credential: credential, resourceKeys: resourceKeys)
            if child.isFolder {
                let (childCount, childBytes, childBreakdown) = try await estimateFolderContents(folderID: child.id, credential: credential, resourceKeys: updatedKeys)
                count += childCount
                bytes += childBytes
                breakdown.images += childBreakdown.images
                breakdown.videos += childBreakdown.videos
                breakdown.documents += childBreakdown.documents
                breakdown.archives += childBreakdown.archives
                breakdown.other += childBreakdown.other
            } else if Self.isDownloadable(mimeType: child.mimeType) {
                count += 1
                bytes += child.size ?? 0
                let category = FileCategoryClassifier.categorize(mimeType: child.mimeType, name: child.name)
                breakdown[keyPath: category] += 1
            }
        }

        return (count, bytes, breakdown)
    }

    // MARK: - Shortcuts / resource keys

    /// Google Drive "shortcut" items point at a real file/folder elsewhere; they carry
    /// no size or downloadable content of their own. Transparently follows one hop to
    /// the target's real metadata, folding in any resource key the target requires.
    private func resolvingShortcut(
        _ file: DriveFile,
        credential: DriveCredential,
        resourceKeys: [String: String]
    ) async throws -> (DriveFile, [String: String]) {
        guard file.isShortcut, let details = file.shortcutDetails else {
            return (file, resourceKeys)
        }

        var updatedKeys = resourceKeys
        if let targetKey = details.targetResourceKey {
            updatedKeys[details.targetId] = targetKey
        }

        let target = try await fetchMetadata(fileID: details.targetId, credential: credential, resourceKeys: updatedKeys)
        return (target, updatedKeys)
    }

    private nonisolated static func applyResourceKeys(_ resourceKeys: [String: String], to request: inout URLRequest) {
        guard !resourceKeys.isEmpty else { return }
        let value = resourceKeys.map { "\($0.key)/\($0.value)" }.joined(separator: ",")
        request.setValue(value, forHTTPHeaderField: "X-Goog-Drive-Resource-Keys")
    }

    // MARK: - Download

    @discardableResult
    func download(_ request: DownloadRequest, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        var resourceKeys = request.resourceKey.map { [request.itemID: $0] } ?? [:]
        let credential = try await resolveCredential(for: request.itemID, resourceKeys: resourceKeys)

        progress(DownloadProgress(currentFileName: "Reading details…"))
        let rawMetadata = try await fetchMetadata(fileID: request.itemID, credential: credential, resourceKeys: resourceKeys)
        let (rootMetadata, updatedKeys) = try await resolvingShortcut(rawMetadata, credential: credential, resourceKeys: resourceKeys)
        resourceKeys = updatedKeys

        guard !rootMetadata.isFolder else {
            return try await downloadFolder(rootMetadata, request: request, credential: credential, resourceKeys: resourceKeys, progress: progress)
        }

        guard Self.isDownloadable(mimeType: rootMetadata.mimeType) else {
            throw DriveDownloadError.unsupportedFileType
        }

        progress(DownloadProgress(currentFileName: rootMetadata.name, totalFiles: 1, totalBytes: rootMetadata.size ?? 0))
        let tracker = ProgressTracker(totalFiles: 1, totalBytes: rootMetadata.size ?? 0)
        let fileURL = try await downloadFile(
            rootMetadata,
            into: request.destinationURL,
            credential: credential,
            resourceKeys: resourceKeys,
            resumeID: request.resumeID
        ) { chunkSize in
            if let update = tracker.addingBytes(chunkSize) {
                progress(update)
            }
        }
        progress(tracker.completingFile())
        return fileURL
    }

    private func downloadFolder(
        _ rootMetadata: DriveFile,
        request: DownloadRequest,
        credential: DriveCredential,
        resourceKeys: [String: String],
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        let rootFolderURL = Self.resolvedRootFolderURL(name: rootMetadata.name, itemID: request.itemID, in: request.destinationURL)
        try FileManager.default.createDirectory(at: rootFolderURL, withIntermediateDirectories: true)
        Self.writeResumeMarker(itemID: request.itemID, in: rootFolderURL)

        progress(DownloadProgress(currentFileName: "Scanning folder contents…"))
        let plan = try await enumerate(folderID: request.itemID, into: rootFolderURL, credential: credential, resourceKeys: resourceKeys)

        let totalBytes = plan.reduce(Int64(0)) { $0 + ($1.file.size ?? 0) }
        let alreadyDone = plan.filter { FileManager.default.fileExists(atPath: $0.destinationFolderURL.appendingPathComponent(Self.fileName(for: $0.file)).path) }
        let completedBytes = alreadyDone.reduce(Int64(0)) { $0 + ($1.file.size ?? 0) }
        let tracker = ProgressTracker(totalFiles: plan.count, totalBytes: totalBytes, completedFiles: alreadyDone.count, bytesDownloaded: completedBytes)

        for item in plan {
            try Task.checkCancellation()
            let expectedPath = item.destinationFolderURL.appendingPathComponent(Self.fileName(for: item.file)).path
            guard !FileManager.default.fileExists(atPath: expectedPath) else {
                continue // already downloaded in a prior attempt at this same item — resume, don't redo it
            }

            progress(tracker.startingFile(item.file.name))
            try await downloadFile(
                item.file,
                into: item.destinationFolderURL,
                credential: credential,
                resourceKeys: resourceKeys,
                resumeID: request.resumeID
            ) { chunkSize in
                if let update = tracker.addingBytes(chunkSize) {
                    progress(update)
                }
            }
            progress(tracker.completingFile())
        }

        Self.clearResumeMarker(itemID: request.itemID, in: rootFolderURL)
        return rootFolderURL
    }

    /// Prefers anonymous API-key access when the item is publicly reachable; falls back
    /// to an authenticated OAuth token (prompting sign-in if necessary) otherwise.
    private func resolveCredential(for itemID: String, resourceKeys: [String: String]) async throws -> DriveCredential {
        // Prior analysis already determined public/private for this item — reuse that
        // instead of re-probing anonymous access with another network round trip.
        if let apiKey = Self.configuredAPIKey,
           case .success(let analysis) = await AnalysisCache.shared.get(itemID),
           analysis.isPublic {
            return .apiKey(apiKey)
        }

        if await AnalysisCache.shared.get(itemID) == nil, let apiKey = Self.configuredAPIKey,
           (try? await fetchMetadata(fileID: itemID, credential: .apiKey(apiKey), resourceKeys: resourceKeys)) != nil {
            return .apiKey(apiKey)
        }

        let token = try await loginManager.validAccessToken()
        return .oauth(token)
    }

    private struct PlanItem {
        let file: DriveFile
        let destinationFolderURL: URL
    }

    private func enumerate(
        folderID: String,
        into localFolderURL: URL,
        credential: DriveCredential,
        resourceKeys: [String: String]
    ) async throws -> [PlanItem] {
        try Task.checkCancellation()
        let children = try await listChildren(of: folderID, credential: credential, resourceKeys: resourceKeys)
        var items: [PlanItem] = []

        for rawChild in children {
            let (child, updatedKeys) = try await resolvingShortcut(rawChild, credential: credential, resourceKeys: resourceKeys)
            if child.isFolder {
                let childURL = localFolderURL.appendingPathComponent(Self.sanitizedName(child.name), isDirectory: true)
                try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
                items.append(contentsOf: try await enumerate(folderID: child.id, into: childURL, credential: credential, resourceKeys: updatedKeys))
            } else if Self.isDownloadable(mimeType: child.mimeType) {
                items.append(PlanItem(file: child, destinationFolderURL: localFolderURL))
            }
        }

        return items
    }

    private func fetchMetadata(fileID: String, credential: DriveCredential, resourceKeys: [String: String]) async throws -> DriveFile {
        var components = URLComponents(string: "\(Self.apiBase)/\(fileID)")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: Self.metadataFields),
            URLQueryItem(name: "supportsAllDrives", value: "true")
        ]
        credential.applying(to: &components)

        var request = URLRequest(url: components.url!)
        credential.applying(to: &request)
        Self.applyResourceKeys(resourceKeys, to: &request)

        let (data, response) = try await urlSession.data(for: request)
        try Self.validate(response, data: data)
        return try JSONDecoder().decode(DriveFile.self, from: data)
    }

    private func listChildren(of folderID: String, credential: DriveCredential, resourceKeys: [String: String]) async throws -> [DriveFile] {
        var files: [DriveFile] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(string: Self.apiBase)!
            var queryItems = [
                URLQueryItem(name: "q", value: "'\(folderID)' in parents and trashed = false"),
                URLQueryItem(name: "fields", value: Self.listFields),
                URLQueryItem(name: "pageSize", value: "1000"),
                URLQueryItem(name: "supportsAllDrives", value: "true"),
                URLQueryItem(name: "includeItemsFromAllDrives", value: "true"),
                URLQueryItem(name: "corpora", value: "allDrives")
            ]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems
            credential.applying(to: &components)

            var request = URLRequest(url: components.url!)
            credential.applying(to: &request)
            Self.applyResourceKeys(resourceKeys, to: &request)

            let (data, response) = try await urlSession.data(for: request)
            try Self.validate(response, data: data)

            let decoded = try JSONDecoder().decode(DriveListResponse.self, from: data)
            files.append(contentsOf: decoded.files)
            pageToken = decoded.nextPageToken
        } while pageToken != nil

        return files
    }

    /// Streams via URLSessionDownloadTask: the OS writes network-sized chunks
    /// directly to a temp file (no per-byte Swift-level iteration), and
    /// DownloadTaskCoordinator moves it to `destinationURL` on completion.
    /// Resumes from previously-saved resume data when it matches this exact file,
    /// and transparently splits large plain files into concurrent ranged requests
    /// when the server supports it and no resume is in play.
    @discardableResult
    private func downloadFile(
        _ file: DriveFile,
        into folderURL: URL,
        credential: DriveCredential,
        resourceKeys: [String: String],
        resumeID: UUID,
        onBytes: @escaping @Sendable (Int64) -> Void
    ) async throws -> URL {
        let destinationURL: URL
        let requestURL: URL
        let isExport: Bool

        if let export = Self.exportMimeTypes[file.mimeType] {
            isExport = true
            destinationURL = folderURL.appendingPathComponent(
                Self.fileName(file.name, withExtension: export.fileExtension)
            )
            var components = URLComponents(string: "\(Self.apiBase)/\(file.id)/export")!
            components.queryItems = [URLQueryItem(name: "mimeType", value: export.mimeType)]
            credential.applying(to: &components)
            requestURL = components.url!
        } else {
            isExport = false
            destinationURL = folderURL.appendingPathComponent(Self.sanitizedName(file.name))
            var components = URLComponents(string: "\(Self.apiBase)/\(file.id)")!
            components.queryItems = [
                URLQueryItem(name: "alt", value: "media"),
                URLQueryItem(name: "supportsAllDrives", value: "true")
            ]
            credential.applying(to: &components)
            requestURL = components.url!
        }

        let envelope = ResumeEnvelopeStore.load(for: resumeID)
        let matchingResumeData = envelope?.fileName == destinationURL.lastPathComponent ? envelope?.data : nil
        if envelope != nil, matchingResumeData == nil {
            ResumeEnvelopeStore.clear(for: resumeID) // stale — belongs to a different file
        }

        if matchingResumeData == nil, !isExport, let expectedSize = file.size, expectedSize > Self.multiPartThresholdBytes,
           await supportsRangeRequests(url: requestURL, credential: credential, resourceKeys: resourceKeys) {
            do {
                try await multiPartDownload(
                    requestURL: requestURL,
                    credential: credential,
                    resourceKeys: resourceKeys,
                    destinationURL: destinationURL,
                    totalBytes: expectedSize,
                    onBytes: onBytes
                )
                ResumeEnvelopeStore.clear(for: resumeID)
                return destinationURL
            } catch {
                try? FileManager.default.removeItem(at: destinationURL)
                // A cancelled/paused part surfaces the same DownloadInterruption error as a
                // genuinely failed one, so the only reliable signal for "the user stopped
                // this, don't silently start a fresh single-stream download instead" is
                // whether the task itself was cancelled — not the error type.
                if Task.isCancelled {
                    throw CancellationError()
                }
                // Otherwise a real per-part failure (not a cancellation): falls through to
                // the single-stream path below.
            }
        }

        var request = URLRequest(url: requestURL)
        credential.applying(to: &request)
        Self.applyResourceKeys(resourceKeys, to: &request)

        let coordinator = DownloadTaskCoordinator(destinationURL: destinationURL, onBytes: onBytes)
        // Ephemeral: a one-shot binary file download has no business populating
        // the shared URL cache or cookie storage.
        let session = URLSession(configuration: .ephemeral, delegate: coordinator, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        do {
            let result: URL
            if let matchingResumeData {
                result = try await coordinator.resume(session: session, resumeData: matchingResumeData)
            } else {
                result = try await coordinator.run(session: session, request: request)
            }
            ResumeEnvelopeStore.clear(for: resumeID)
            return result
        } catch let interruption as DownloadInterruption {
            if let resumeData = interruption.resumeData {
                ResumeEnvelopeStore.save(ResumeEnvelope(fileName: destinationURL.lastPathComponent, data: resumeData), for: resumeID)
            } else {
                ResumeEnvelopeStore.clear(for: resumeID)
            }
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    // MARK: - Multi-threaded ranged downloads

    private func supportsRangeRequests(url: URL, credential: DriveCredential, resourceKeys: [String: String]) async -> Bool {
        var request = URLRequest(url: url)
        credential.applying(to: &request)
        Self.applyResourceKeys(resourceKeys, to: &request)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        guard let (_, response) = try? await urlSession.data(for: request),
              let http = response as? HTTPURLResponse else {
            return false
        }
        return http.statusCode == 206
    }

    /// Splits the file into `multiPartCount` byte ranges, downloads each concurrently
    /// into its own temp part (reusing DownloadTaskCoordinator, so no byte-by-byte
    /// Swift-level iteration), then concatenates the parts in order into the final
    /// destination. Any part failure throws, and the caller falls back to a normal
    /// single-stream download — multi-part resume isn't supported, only fresh starts.
    private func multiPartDownload(
        requestURL: URL,
        credential: DriveCredential,
        resourceKeys: [String: String],
        destinationURL: URL,
        totalBytes: Int64,
        onBytes: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DropDrive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ranges = Self.splitRanges(totalBytes: totalBytes, partCount: Self.multiPartCount)

        let parts = try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            for (index, range) in ranges.enumerated() {
                group.addTask {
                    var partRequest = URLRequest(url: requestURL)
                    credential.applying(to: &partRequest)
                    Self.applyResourceKeys(resourceKeys, to: &partRequest)
                    partRequest.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")

                    let partURL = tempDir.appendingPathComponent("part\(index)")
                    let coordinator = DownloadTaskCoordinator(destinationURL: partURL, onBytes: onBytes, requireStatusCode: 206)
                    let session = URLSession(configuration: .ephemeral, delegate: coordinator, delegateQueue: nil)
                    defer { session.finishTasksAndInvalidate() }
                    _ = try await coordinator.run(session: session, request: partRequest)
                    return (index, partURL)
                }
            }

            var collected: [Int: URL] = [:]
            for try await (index, url) in group {
                collected[index] = url
            }
            return collected
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: destinationURL)
        defer { try? output.close() }

        for index in 0..<Self.multiPartCount {
            guard let partURL = parts[index] else { throw DriveDownloadError.invalidResponse }
            let input = try FileHandle(forReadingFrom: partURL)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                output.write(chunk)
            }
        }
    }

    private static func splitRanges(totalBytes: Int64, partCount: Int) -> [ClosedRange<Int64>] {
        let partSize = totalBytes / Int64(partCount)
        var ranges: [ClosedRange<Int64>] = []
        var start: Int64 = 0
        for index in 0..<partCount {
            let end = index == partCount - 1 ? totalBytes - 1 : start + partSize - 1
            ranges.append(start...max(start, end))
            start = end + 1
        }
        return ranges
    }

    private static func validate(_ response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DriveDownloadError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
            throw DriveDownloadError.server(httpResponse.statusCode, message)
        }
    }

    // MARK: - Naming

    private static func sanitizedName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
        return name.components(separatedBy: invalidCharacters).joined(separator: "-")
    }

    private static func fileName(_ name: String, withExtension fileExtension: String) -> String {
        let sanitized = sanitizedName(name)
        if sanitized.lowercased().hasSuffix(".\(fileExtension)") {
            return sanitized
        }
        return "\(sanitized).\(fileExtension)"
    }

    private static func fileName(for file: DriveFile) -> String {
        if let export = exportMimeTypes[file.mimeType] {
            return fileName(file.name, withExtension: export.fileExtension)
        }
        return sanitizedName(file.name)
    }

    private static let resumeMarkerName = ".dropdrive-inprogress"

    /// A brand-new folder download gets a collision-safe unique name (Feature 13). A
    /// folder we're resuming into (marked below) reuses the exact same path instead —
    /// otherwise every resume attempt would uniquify itself into a fresh "(1)", "(2)"...
    private static func resolvedRootFolderURL(name: String, itemID: String, in destinationURL: URL) -> URL {
        let candidate = destinationURL.appendingPathComponent(sanitizedName(name), isDirectory: true)
        let marker = candidate.appendingPathComponent(resumeMarkerName)
        if let ownerID = try? String(contentsOf: marker, encoding: .utf8), ownerID == itemID {
            return candidate
        }
        return UniqueDestinationNaming.uniqueURL(for: candidate)
    }

    private static func writeResumeMarker(itemID: String, in folderURL: URL) {
        let marker = folderURL.appendingPathComponent(resumeMarkerName)
        try? itemID.write(to: marker, atomically: true, encoding: .utf8)
    }

    private static func clearResumeMarker(itemID: String, in folderURL: URL) {
        try? FileManager.default.removeItem(at: folderURL.appendingPathComponent(resumeMarkerName))
    }
}

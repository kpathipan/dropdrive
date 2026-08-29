import Foundation
import CryptoKit
import UniformTypeIdentifiers

/// `nonisolated` on the protocol, not just the implementation: the requirement's
/// own isolation is what the caller adopts, so leaving it at the project's
/// MainActor default meant every download ran its filesystem work — creating a
/// folder's directory tree, statting thousands of planned files, sweeping stale
/// staging files, truncating and renaming — on the main thread, with the window
/// unable to redraw until it finished.
nonisolated protocol DownloadServicing: Sendable {
    @discardableResult
    func download(_ request: DownloadRequest, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL
    func analyzeLink(itemID: String, resourceKey: String?) async throws -> LinkAnalysisResult
    func clearAnalysisCache() async
}

nonisolated struct DriveFile: Decodable, Sendable {
    private nonisolated struct Owner: Decodable {
        let displayName: String?
    }

    nonisolated struct ShortcutDetails: Decodable {
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
    let md5Checksum: String?
    let modifiedTime: String?
    let thumbnailLink: String?
    let thumbnailVersion: String?

    var isFolder: Bool { mimeType == "application/vnd.google-apps.folder" }
    var isShortcut: Bool { mimeType == "application/vnd.google-apps.shortcut" }

    private enum CodingKeys: String, CodingKey {
        case id, name, mimeType, size, owners, shortcutDetails, resourceKey, md5Checksum, modifiedTime,
             thumbnailLink, thumbnailVersion
    }

    init(
        id: String,
        name: String,
        mimeType: String,
        size: Int64?,
        resourceKey: String?,
        md5Checksum: String? = nil,
        modifiedTime: String? = nil,
        thumbnailLink: String? = nil,
        thumbnailVersion: String? = nil
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.size = size
        self.ownerName = nil
        self.shortcutDetails = nil
        self.resourceKey = resourceKey
        self.md5Checksum = md5Checksum
        self.modifiedTime = modifiedTime
        self.thumbnailLink = thumbnailLink
        self.thumbnailVersion = thumbnailVersion
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
        md5Checksum = try container.decodeIfPresent(String.self, forKey: .md5Checksum)
        modifiedTime = try container.decodeIfPresent(String.self, forKey: .modifiedTime)
        thumbnailLink = try container.decodeIfPresent(String.self, forKey: .thumbnailLink)
        thumbnailVersion = try container.decodeIfPresent(String.self, forKey: .thumbnailVersion)
    }
}

private nonisolated struct DriveListResponse: Decodable, Sendable {
    let files: [DriveFile]
    let nextPageToken: String?
}

enum DriveDownloadError: LocalizedError {
    case invalidResponse
    case server(Int, String)
    case unsupportedFileType
    case integrityMismatch(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Received an unexpected response from Google Drive."
        case .server(let statusCode, let message):
            "Google Drive returned an error (\(statusCode)): \(message)"
        case .unsupportedFileType:
            "This file type can't be downloaded directly from Google Drive."
        case .integrityMismatch(let fileName):
            "The downloaded bytes for \(fileName) didn't match Google Drive's checksum."
        }
    }
}

/// Thrown when a download stops early with resume data worth keeping, so the
/// caller can persist it before deciding what the stop actually meant.
///
/// `cause` is what separates the two, and the separation matters: a stop the
/// user asked for is a cancellation, while a stop the network caused is a
/// failure that should retry. URLSession hands back resume data for both — it
/// attaches it to any error a range-supporting server allows resuming from, and
/// Drive supports ranges — so resume data alone cannot tell them apart. Reading
/// it as "cancelled" meant a dropped connection was recorded as though the user
/// had pressed Cancel: the resume data was cleared again, a partly-downloaded
/// folder was deleted as unwanted, and the auto-retry never ran.
private struct DownloadInterruption: Error {
    let resumeData: Data?
    /// Nil for a real cancellation or pause; the network error otherwise.
    let cause: Error?
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

    /// Bounded so a long-running session can't accumulate every link ever
    /// pasted; folder analyses now hold a selectable file manifest. Twenty hot
    /// links keeps re-pastes instant without retaining large folder trees for
    /// the lifetime of a menu-bar process.
    private static let capacity = 20

    private var storage: [String: LinkAnalysisResult] = [:]
    private var insertionOrder: [String] = []

    func get(_ key: String) -> LinkAnalysisResult? {
        storage[key]
    }

    func set(_ key: String, _ value: LinkAnalysisResult) {
        // Tracked by key rather than by comparing the stored value: the result
        // type's `Equatable` conformance is main-actor isolated and can't be
        // used from inside this actor.
        if storage.index(forKey: key) == nil {
            insertionOrder.append(key)
        }
        storage[key] = value
        while insertionOrder.count > Self.capacity {
            storage.removeValue(forKey: insertionOrder.removeFirst())
        }
    }

    func clear() {
        storage.removeAll()
        insertionOrder.removeAll()
    }
}

/// Remembers, per host, whether ranged requests are honoured. Whether a server
/// answers 206 is a property of the server rather than of any one file, so the
/// probe only needs to happen once per session instead of once per large file.
private actor RangeSupportCache {
    static let shared = RangeSupportCache()

    private var storage: [String: Bool] = [:]

    func get(_ host: String) -> Bool? { storage[host] }
    func set(_ host: String, _ supported: Bool) { storage[host] = supported }
}

/// Delegate-based downloads deliver `didWriteData` callbacks on URLSession's own
/// delegate queue — a different thread than whatever context `download()` itself
/// runs on — so this now needs real thread-safety, not just single-threaded
/// sequential access. Protected by a lock rather than an actor: its methods are
/// small, synchronous, and called from a non-async delegate callback, so making
/// them `async` would force a Task-per-callback right back into the hot path.
// `nonisolated` on the type, not just its methods: it opted into `@unchecked
// Sendable` and does its own NSLock-based synchronization specifically so it can
// be called from any thread/task — concurrent folder-download workers included,
// none of them MainActor. This project defaults every declaration to MainActor
// isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), which applies
// per-property as well as per-method — marking only the methods `nonisolated`
// left their own stored-property accesses isolated to the main actor and just
// moved the warning inside the lock. Opting the whole type out is what the
// class's own locking already assumed.
private nonisolated final class ProgressTracker: @unchecked Sendable {
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

        // A failed parallel attempt hands its bytes back as a negative count so
        // the total stays honest, which makes this delta negative for one
        // sample. Clamped, or the readout briefly shows a negative speed.
        let deltaBytes = max(0, bytesDownloaded - lastSampleBytes)
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

/// Thread-safe tally of bytes a single download attempt reported.
private nonisolated final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 0

    func add(_ count: Int64) {
        lock.lock(); value += count; lock.unlock()
    }

    var total: Int64 {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

/// Streams one ranged response straight into its slice of the final file.
///
/// The multi-part path used to download each range to its own temp file and
/// concatenate them at the end, which meant a download briefly needed about
/// twice the file's size on disk — the very "download, then unpack" overhead
/// this app exists to avoid. Writing each range at its own offset instead means
/// the only space consumed is the file itself, and there is no assembly pass to
/// wait through (or to re-read and re-write every byte for).
private final class RangedStreamCoordinator: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let fileHandle: FileHandle
    private let onBytes: @Sendable (Int64) -> Void

    private let stateLock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDataTask?
    private var didResume = false
    private var failure: Error?
    /// Set when cancellation arrives before there is a task to cancel — see `run`.
    private var cancelledEarly = false

    private let expectedBytes: Int64
    private var writtenBytes: Int64 = 0

    init(
        fileHandle: FileHandle,
        startOffset: UInt64,
        expectedBytes: Int64,
        onBytes: @escaping @Sendable (Int64) -> Void
    ) throws {
        self.fileHandle = fileHandle
        self.expectedBytes = expectedBytes
        self.onBytes = onBytes
        super.init()
        try fileHandle.seek(toOffset: startOffset)
    }

    /// `onCancel` can fire before the body has created the task — a task
    /// cancelled in the window between the group scheduling it and it starting
    /// would otherwise find nothing to cancel and then download the whole range
    /// anyway, ignoring the pause the user just asked for.
    func run(session: URLSession, request: URLRequest) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                stateLock.lock()
                self.continuation = continuation
                let task = session.dataTask(with: request)
                self.task = task
                let alreadyCancelled = cancelledEarly
                stateLock.unlock()
                task.resume()
                if alreadyCancelled { task.cancel() }
            }
        } onCancel: { [weak self] in
            guard let self else { return }
            stateLock.lock()
            let task = self.task
            if task == nil { cancelledEarly = true }
            stateLock.unlock()
            task?.cancel()
        }
    }

    private func complete(_ result: Result<Void, Error>) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !didResume else { return }
        didResume = true
        try? fileHandle.close()
        switch result {
        case .success:
            continuation?.resume()
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    /// A server that ignores `Range` answers 200 with the whole file; accepting
    /// that here would write the entire file into one slice's offset and corrupt
    /// the result, so only 206 is allowed through.
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 206 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            stateLock.lock(); failure = DriveDownloadError.server(code, "Expected a ranged (206) response"); stateLock.unlock()
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        BandwidthLimiter.shared.throttle(bytes: Int64(data.count))
        do {
            try fileHandle.write(contentsOf: data)
            stateLock.lock(); writtenBytes += Int64(data.count); stateLock.unlock()
            onBytes(Int64(data.count))
        } catch {
            stateLock.lock(); failure = error; stateLock.unlock()
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        stateLock.lock()
        let recorded = failure
        let written = writtenBytes
        stateLock.unlock()

        if let recorded {
            complete(.failure(recorded))
        } else if let error {
            complete(.failure(error))
        } else if written != expectedBytes {
            // A server is allowed to answer a range request with *less* than was
            // asked for. Silently accepting that would leave the untouched tail
            // of this slice as zeros in a file that otherwise looks complete, so
            // treat a short range as a failure and let the caller fall back.
            complete(.failure(DriveDownloadError.server(206, "Range returned \(written) of \(expectedBytes) bytes")))
        } else {
            complete(.success(()))
        }
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
    /// See `RangedStreamCoordinator.run` — cancellation can beat the task into
    /// existence, and a download that ignores it keeps running to completion.
    private var cancelledEarly = false

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
                let alreadyCancelled = cancelledEarly
                stateLock.unlock()
                task.resume()
                if alreadyCancelled { task.cancel { _ in } }
            }
        } onCancel: { [weak self] in
            guard let self else { return }
            stateLock.lock()
            let task = self.task
            if task == nil { cancelledEarly = true }
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
                let alreadyCancelled = cancelledEarly
                stateLock.unlock()
                task.resume()
                if alreadyCancelled { task.cancel { _ in } }
            }
        } onCancel: { [weak self] in
            guard let self else { return }
            stateLock.lock()
            let task = self.task
            if task == nil { cancelledEarly = true }
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

        if nsError.code == NSURLErrorCancelled {
            complete(.failure(DownloadInterruption(resumeData: resumeData, cause: nil)))
        } else if resumeData != nil {
            // A network failure the server will let us pick back up: keep the
            // resume data, but report it as the failure it is so the retry
            // logic — not the cancellation path — handles it.
            complete(.failure(DownloadInterruption(resumeData: resumeData, cause: error)))
        } else {
            complete(.failure(error))
        }
    }
}

nonisolated struct GoogleDriveDownloadService: DownloadServicing {
    private static let apiBase = "https://www.googleapis.com/drive/v3/files"
    private static let metadataFields = "id,name,mimeType,size,md5Checksum,modifiedTime,thumbnailLink,thumbnailVersion,owners(displayName),shortcutDetails(targetId,targetMimeType,targetResourceKey),resourceKey"
    private static let listFields = "nextPageToken, files(id, name,mimeType,size,md5Checksum,modifiedTime,thumbnailLink,thumbnailVersion,shortcutDetails(targetId,targetMimeType,targetResourceKey),resourceKey)"

    /// Multi-part ranged downloads only pay off past this size; below it the extra
    /// round trips (probe + N connection setups) aren't worth it.
    private static let multiPartThresholdBytes: Int64 = 20 * 1024 * 1024

    /// Drive throttles each connection to a few MB/s regardless of the link's real
    /// capacity, so throughput on a single file scales with the number of streams,
    /// not with bandwidth. A big file therefore earns more connections than a
    /// merely large one — with a ceiling, since past this the per-connection
    /// setup and Drive's own per-item rate limiting take the gains back.
    private static func multiPartCount(forSize bytes: Int64) -> Int {
        switch bytes {
        case ..<(200 * 1024 * 1024): 4
        case ..<(1024 * 1024 * 1024): 6
        default: 8
        }
    }

    /// One folder scan can list hundreds of subfolders; walking them one at a
    /// time meant the whole tree cost one round trip after another. Sibling
    /// folders are now listed concurrently, capped here so a wide tree can't turn
    /// into a burst big enough for Drive to start answering 429.
    private static let maxConcurrentListings = 6

    /// `JSONDecoder` is stateless for our purposes but not free to construct, and
    /// a folder scan decodes one response per page per folder.
    private static let decoder = JSONDecoder()

    /// A folder full of small files used to download one at a time, so most of the
    /// wall-clock time was per-file round-trip latency rather than actual transfer —
    /// a 266-file folder paid that latency 266 times over. Downloading several files
    /// at once amortizes it; kept modest since each concurrent file can itself still
    /// split into `multiPartCount` ranged connections once it's large enough.
    private static let maxConcurrentFileDownloads = 5

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

        let (fileCount, totalBytes, breakdown, folderItems) = try await estimateFolderContents(folderID: metadata.id, credential: credential, resourceKeys: resourceKeys)
        return DriveLinkAnalysis(
            itemID: metadata.id,
            name: metadata.name,
            type: .folder,
            isPublic: isPublic,
            requiresAuthentication: !isPublic,
            totalBytes: totalBytes,
            fileCount: fileCount,
            ownerName: metadata.ownerName,
            categoryBreakdown: breakdown,
            folderItems: folderItems
        )
    }

    /// Walks the tree breadth-first, listing up to `maxConcurrentListings` folders
    /// at a time. Depth-first recursion made every folder wait for the previous
    /// one's round trip, so a tree's analysis cost the sum of all its listings;
    /// one bounded task group per level means it costs roughly the deepest path
    /// instead, without ever having more requests in flight than the cap.
    private func estimateFolderContents(
        folderID: String,
        credential: DriveCredential,
        resourceKeys: [String: String]
    ) async throws -> (fileCount: Int, totalBytes: Int64, breakdown: DriveLinkAnalysis.CategoryBreakdown, folderItems: [DriveLinkAnalysis.FolderItem]) {
        var count = 0
        var bytes: Int64 = 0
        var breakdown = DriveLinkAnalysis.CategoryBreakdown()
        var folderItems: [DriveLinkAnalysis.FolderItem] = []

        // A folder reachable from itself through a shortcut would otherwise be
        // walked forever — the old depth-first version would at least have run
        // out of stack; this one would just never finish.
        var visited: Set<String> = [folderID]
        var frontier: [FolderScan] = [FolderScan(id: folderID, resourceKeys: resourceKeys, relativePath: "")]
        while !frontier.isEmpty {
            var next: [FolderScan] = []
            let level = try await scanLevel(frontier, credential: credential)
            for (folder, resolved) in zip(frontier, level) {
                for (child, childKeys) in resolved {
                    if child.isFolder {
                        guard visited.insert(child.id).inserted else { continue }
                        let path = [folder.relativePath, Self.sanitizedName(child.name)]
                            .filter { !$0.isEmpty }.joined(separator: "/")
                        next.append(FolderScan(id: child.id, resourceKeys: childKeys, relativePath: path))
                    } else if Self.isDownloadable(mimeType: child.mimeType) {
                        count += 1
                        bytes += child.size ?? 0
                        let category = FileCategoryClassifier.categorize(mimeType: child.mimeType, name: child.name)
                        breakdown[keyPath: category] += 1
                        let relativePath = [folder.relativePath, Self.fileName(for: child)]
                            .filter { !$0.isEmpty }.joined(separator: "/")
                        folderItems.append(.init(
                            id: child.id,
                            name: Self.fileName(for: child),
                            relativePath: relativePath,
                            mimeType: child.mimeType,
                            size: child.size,
                            category: FileCategoryClassifier.category(mimeType: child.mimeType, name: child.name),
                            resourceKey: childKeys[child.id] ?? child.resourceKey,
                            md5Checksum: child.md5Checksum,
                            modifiedTime: child.modifiedTime,
                            thumbnailLink: child.thumbnailLink,
                            thumbnailVersion: child.thumbnailVersion
                        ))
                    }
                }
            }
            frontier = next
        }

        folderItems.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        return (count, bytes, breakdown, folderItems)
    }

    /// One folder queued for listing: its Drive ID, the resource keys reaching it,
    /// and (when building a download plan) where its contents land locally.
    private struct FolderScan: Sendable {
        let id: String
        let resourceKeys: [String: String]
        var localURL: URL?
        var relativePath: String = ""
    }

    /// Lists every folder in one level of the tree concurrently and returns their
    /// shortcut-resolved children, in the same order the folders were given —
    /// callers depend on that for a stable download order.
    private func scanLevel(
        _ folders: [FolderScan],
        credential: DriveCredential
    ) async throws -> [[(DriveFile, [String: String])]] {
        try Task.checkCancellation()

        var pending = Array(folders.enumerated())[...]
        var results = [[(DriveFile, [String: String])]](repeating: [], count: folders.count)

        try await withThrowingTaskGroup(of: (Int, [(DriveFile, [String: String])]).self) { group in
            func startNext() {
                guard let (index, folder) = pending.popFirst() else { return }
                group.addTask {
                    let children = try await listChildren(
                        of: folder.id,
                        credential: credential,
                        resourceKeys: folder.resourceKeys
                    )
                    var resolved: [(DriveFile, [String: String])] = []
                    resolved.reserveCapacity(children.count)
                    for rawChild in children {
                        resolved.append(try await resolvingShortcut(
                            rawChild,
                            credential: credential,
                            resourceKeys: folder.resourceKeys
                        ))
                    }
                    return (index, resolved)
                }
            }

            for _ in 0..<Self.maxConcurrentListings { startNext() }
            while let (index, resolved) = try await group.next() {
                results[index] = resolved
                startNext()
            }
        }

        return results
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

    private static func applyResourceKeys(_ resourceKeys: [String: String], to request: inout URLRequest) {
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
            resumeID: request.resumeID,
            avoidingOverwrite: true,
            overrideBaseName: request.customName
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
        let rootFolderURL = Self.resolvedRootFolderURL(
            name: request.customName ?? rootMetadata.name,
            itemID: request.itemID,
            in: request.destinationURL
        )
        try FileManager.default.createDirectory(at: rootFolderURL, withIntermediateDirectories: true)
        Self.writeResumeMarker(itemID: request.itemID, in: rootFolderURL)

        progress(DownloadProgress(currentFileName: request.selectedFolderItems == nil
            ? "Scanning folder contents…"
            : "Preparing selected files…"))
        let plan: [PlanItem]
        var downloadResourceKeys = resourceKeys
        if let selectedFolderItems = request.selectedFolderItems {
            var direct: [PlanItem] = []
            direct.reserveCapacity(selectedFolderItems.count)
            for item in selectedFolderItems {
                let relativeDirectory = (item.relativePath as NSString).deletingLastPathComponent
                let destinationFolder = relativeDirectory.isEmpty
                    ? rootFolderURL
                    : rootFolderURL.appendingPathComponent(relativeDirectory, isDirectory: true)
                try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                if let resourceKey = item.resourceKey { downloadResourceKeys[item.id] = resourceKey }
                direct.append(PlanItem(
                    file: DriveFile(
                        id: item.id,
                        name: item.name,
                        mimeType: item.mimeType,
                        size: item.size,
                        resourceKey: item.resourceKey,
                        md5Checksum: item.md5Checksum
                    ),
                    destinationFolderURL: destinationFolder
                ))
            }
            plan = Self.withUniqueLocalNames(direct)
        } else {
            let completePlan = try await enumerate(folderID: request.itemID, into: rootFolderURL, credential: credential, resourceKeys: resourceKeys)
            if let selectedFileIDs = request.selectedFileIDs {
                plan = completePlan.filter { selectedFileIDs.contains($0.file.id) }
            } else {
                plan = completePlan
            }
        }

        // Half-written files from a run that was killed rather than cancelled:
        // clear them so this attempt restarts those files cleanly.
        Self.removePartialFiles(in: rootFolderURL)

        // One `stat` per planned file, not three: the totals, the already-done
        // tally, and the remaining work all come out of the same pass. A folder
        // with thousands of files paid for every extra pass in syscalls before
        // a single byte moved.
        var totalBytes: Int64 = 0
        var completedFiles = 0
        var completedBytes: Int64 = 0
        var pending: [PlanItem] = []
        pending.reserveCapacity(plan.count)

        for item in plan {
            let size = item.file.size ?? 0
            totalBytes += size
            let path = item.destinationFolderURL.appendingPathComponent(item.localName).path
            if FileManager.default.fileExists(atPath: path) {
                // already downloaded in a prior attempt at this same item — resume, don't redo it
                completedFiles += 1
                completedBytes += size
            } else {
                pending.append(item)
            }
        }

        let tracker = ProgressTracker(totalFiles: plan.count, totalBytes: totalBytes, completedFiles: completedFiles, bytesDownloaded: completedBytes)
        var remaining = pending[...]

        // Bounded-concurrency worker pool: `maxConcurrentFileDownloads` files in
        // flight at once, refilling as each finishes, rather than the unbounded
        // fan-out multiPartDownload uses for a single file's byte ranges. If any
        // file throws, leaving this scope cancels every other in-flight download —
        // same "one failure aborts the folder" behavior the sequential loop had.
        try await withThrowingTaskGroup(of: Void.self) { group in
            func startNext() {
                guard let item = remaining.popFirst() else { return }
                group.addTask {
                    try Task.checkCancellation()
                    progress(tracker.startingFile(item.file.name))
                    try await downloadFile(
                        item.file,
                        into: item.destinationFolderURL,
                        credential: credential,
                        resourceKeys: downloadResourceKeys,
                        resumeID: request.resumeID,
                        overrideBaseName: item.localName
                    ) { chunkSize in
                        if let update = tracker.addingBytes(chunkSize) {
                            progress(update)
                        }
                    }
                    progress(tracker.completingFile())
                }
            }

            for _ in 0..<Self.maxConcurrentFileDownloads {
                startNext()
            }
            while try await group.next() != nil {
                startNext()
            }
        }

        Self.clearResumeMarker(itemID: request.itemID, in: rootFolderURL)
        Self.removeEmptyDirectories(in: rootFolderURL)
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

    private struct PlanItem: Sendable {
        let file: DriveFile
        let destinationFolderURL: URL
        /// The name this file will actually be written under, decided once for
        /// the whole plan so that the "is it already on disk?" check and the
        /// download itself can never disagree about it.
        var localName: String = ""
    }

    private static func removeEmptyDirectories(in root: URL) {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let directories = enumerator.compactMap { $0 as? URL }.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { $0.path.count > $1.path.count }
        for directory in directories where directory != root {
            if (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    /// Gives every planned file a name unique within its own folder.
    ///
    /// Drive identifies files by id, not by name, so one folder can genuinely
    /// hold several files called "invoice.pdf". Downloaded as-is they all landed
    /// on the same path and silently overwrote each other — the folder finished
    /// "successfully" with files missing and a count that said otherwise.
    ///
    /// Suffixes are assigned in file-id order rather than in the order Drive
    /// happened to list them, because the result has to be identical on a later
    /// resume: the plan's existence check is what decides a file is already
    /// done, and names that shuffled between runs would re-download some files
    /// and skip others.
    private static func withUniqueLocalNames(_ items: [PlanItem]) -> [PlanItem] {
        var takenPerFolder: [String: Set<String>] = [:]
        var namesByFileID: [String: String] = [:]

        for item in items.sorted(by: { $0.file.id < $1.file.id }) {
            let folder = item.destinationFolderURL.path
            var taken = takenPerFolder[folder] ?? []
            var candidate = fileName(for: item.file)

            if taken.contains(candidate.lowercased()) {
                let fileExtension = (candidate as NSString).pathExtension
                let base = fileExtension.isEmpty ? candidate : String(candidate.dropLast(fileExtension.count + 1))
                var attempt = 2
                repeat {
                    candidate = fileExtension.isEmpty ? "\(base) (\(attempt))" : "\(base) (\(attempt)).\(fileExtension)"
                    attempt += 1
                } while taken.contains(candidate.lowercased())
            }

            taken.insert(candidate.lowercased())
            takenPerFolder[folder] = taken
            namesByFileID[item.file.id] = candidate
        }

        return items.map { item in
            PlanItem(
                file: item.file,
                destinationFolderURL: item.destinationFolderURL,
                localName: namesByFileID[item.file.id] ?? fileName(for: item.file)
            )
        }
    }

    /// Breadth-first for the same reason `estimateFolderContents` is: sibling
    /// folders list concurrently instead of each waiting on the last. Files come
    /// out level by level rather than depth-first, which only changes the order
    /// they're downloaded in.
    private func enumerate(
        folderID: String,
        into localFolderURL: URL,
        credential: DriveCredential,
        resourceKeys: [String: String]
    ) async throws -> [PlanItem] {
        var items: [PlanItem] = []
        var visited: Set<String> = [folderID]
        var frontier = [FolderScan(id: folderID, resourceKeys: resourceKeys, localURL: localFolderURL, relativePath: "")]

        while !frontier.isEmpty {
            var next: [FolderScan] = []
            let level = try await scanLevel(frontier, credential: credential)

            for (folder, resolved) in zip(frontier, level) {
                guard let parentURL = folder.localURL else { continue }
                for (child, childKeys) in resolved {
                    if child.isFolder {
                        // See `estimateFolderContents`: shortcut cycles.
                        guard visited.insert(child.id).inserted else { continue }
                        let childURL = parentURL.appendingPathComponent(Self.sanitizedName(child.name), isDirectory: true)
                        try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
                        next.append(FolderScan(id: child.id, resourceKeys: childKeys, localURL: childURL, relativePath: ""))
                    } else if Self.isDownloadable(mimeType: child.mimeType) {
                        items.append(PlanItem(file: child, destinationFolderURL: parentURL))
                    }
                }
            }

            frontier = next
        }

        return Self.withUniqueLocalNames(items)
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
        return try Self.decoder.decode(DriveFile.self, from: data)
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

            let decoded = try Self.decoder.decode(DriveListResponse.self, from: data)
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
    ///
    /// `avoidingOverwrite` is on only for a lone file the user asked for by
    /// link. Everything that lands at the destination is a *finished* file —
    /// a single stream keeps its partial bytes in system temp and a multi-part
    /// download stages beside the destination under `.dddownload` — so a name
    /// already taken there means a real, unrelated file of the user's, and
    /// writing over it would destroy it. Folder downloads deliberately keep the
    /// plain name: inside a folder, "this file already exists" is how resuming
    /// knows not to fetch it again.
    @discardableResult
    private func downloadFile(
        _ file: DriveFile,
        into folderURL: URL,
        credential: DriveCredential,
        resourceKeys: [String: String],
        resumeID: UUID,
        avoidingOverwrite: Bool = false,
        /// Renames just this file, keeping whatever extension it actually has —
        /// only ever set for the single-file download the user typed a name for,
        /// never for a file inside a folder.
        overrideBaseName: String? = nil,
        onBytes: @escaping @Sendable (Int64) -> Void
    ) async throws -> URL {
        var destinationURL: URL
        let requestURL: URL
        let isExport: Bool

        if let export = Self.exportMimeTypes[file.mimeType] {
            isExport = true
            destinationURL = folderURL.appendingPathComponent(
                Self.fileName(overrideBaseName ?? file.name, withExtension: export.fileExtension)
            )
            var components = URLComponents(string: "\(Self.apiBase)/\(file.id)/export")!
            components.queryItems = [URLQueryItem(name: "mimeType", value: export.mimeType)]
            credential.applying(to: &components)
            requestURL = components.url!
        } else {
            isExport = false
            destinationURL = folderURL.appendingPathComponent(
                Self.renamed(Self.nameWithTypeExtension(file.name, mimeType: file.mimeType), to: overrideBaseName)
            )
            var components = URLComponents(string: "\(Self.apiBase)/\(file.id)")!
            components.queryItems = [
                URLQueryItem(name: "alt", value: "media"),
                URLQueryItem(name: "supportsAllDrives", value: "true")
            ]
            credential.applying(to: &components)
            requestURL = components.url!
        }

        if avoidingOverwrite {
            destinationURL = UniqueDestinationNaming.uniqueURL(for: destinationURL)
        }

        let envelope = ResumeEnvelopeStore.load(for: resumeID)
        let matchingResumeData = envelope?.fileName == destinationURL.lastPathComponent ? envelope?.data : nil
        if envelope != nil, matchingResumeData == nil {
            ResumeEnvelopeStore.clear(for: resumeID) // stale — belongs to a different file
        }

        if matchingResumeData == nil, !isExport, let expectedSize = file.size, expectedSize > Self.multiPartThresholdBytes,
           await supportsRangeRequests(url: requestURL, credential: credential, resourceKeys: resourceKeys) {
            // Bytes this attempt reported, so a fallback can take them back out
            // of the progress total — otherwise the single-stream retry counts
            // the same bytes a second time and the bar sails past 100%.
            let attemptBytes = ByteCounter()
            do {
                try await multiPartDownload(
                    requestURL: requestURL,
                    credential: credential,
                    resourceKeys: resourceKeys,
                    destinationURL: destinationURL,
                    totalBytes: expectedSize,
                    onBytes: { count in
                        attemptBytes.add(count)
                        onBytes(count)
                    }
                )
                try Self.verifyChecksum(of: destinationURL, expectedMD5: file.md5Checksum)
                ResumeEnvelopeStore.clear(for: resumeID)
                return destinationURL
            } catch {
                try? FileManager.default.removeItem(at: destinationURL)
                let counted = attemptBytes.total
                if counted > 0 { onBytes(-counted) }
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
            try Self.verifyChecksum(of: result, expectedMD5: file.md5Checksum)
            ResumeEnvelopeStore.clear(for: resumeID)
            return result
        } catch let interruption as DownloadInterruption {
            if let resumeData = interruption.resumeData {
                ResumeEnvelopeStore.save(ResumeEnvelope(fileName: destinationURL.lastPathComponent, data: resumeData), for: resumeID)
            } else {
                ResumeEnvelopeStore.clear(for: resumeID)
            }
            // The network stopped this, not the user: hand the real error up so
            // it retries and is reported as a failure. Deliberately not deleting
            // the staged bytes here — they are what the saved resume data
            // continues from.
            if let cause = interruption.cause { throw cause }
            throw CancellationError()
        } catch {
            ResumeEnvelopeStore.clear(for: resumeID)
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    /// Google Drive exposes MD5 for uploaded binary files (not native Docs
    /// exports). Hash the completed file in bounded chunks: no extra copy, no
    /// second file, and constant memory even for multi-gigabyte downloads.
    private static func verifyChecksum(of url: URL, expectedMD5: String?) throws {
        guard let expectedMD5, !expectedMD5.isEmpty else { return }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = Insecure.MD5()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual.caseInsensitiveCompare(expectedMD5) == .orderedSame else {
            throw DriveDownloadError.integrityMismatch(url.lastPathComponent)
        }
    }

    // MARK: - Multi-threaded ranged downloads

    /// Whether the host will honour a `Range` header. Answered from a probe the
    /// first time and remembered per host afterwards: the answer is a property of
    /// the server, not of the file, so a folder of large files used to spend one
    /// wasted round trip apiece re-learning the same thing.
    private func supportsRangeRequests(url: URL, credential: DriveCredential, resourceKeys: [String: String]) async -> Bool {
        guard let host = url.host else { return false }
        if let known = await RangeSupportCache.shared.get(host) { return known }

        var request = URLRequest(url: url)
        credential.applying(to: &request)
        Self.applyResourceKeys(resourceKeys, to: &request)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        guard let (_, response) = try? await urlSession.data(for: request),
              let http = response as? HTTPURLResponse else {
            // A failed probe says nothing about the host — don't cache it, or one
            // dropped connection disables multi-part downloads for the session.
            return false
        }
        let supported = http.statusCode == 206
        await RangeSupportCache.shared.set(host, supported)
        return supported
    }

    /// Splits the file into `multiPartCount` byte ranges and downloads them
    /// concurrently, each straight into its own region of the destination file.
    ///
    /// Nothing is staged anywhere else: the file is created at its final size up
    /// front (sparse on APFS, so blocks are only consumed as bytes actually
    /// arrive) and each connection seeks to its range and streams into it. Peak
    /// disk usage is therefore the file itself and nothing more — no temp copies,
    /// and no assembly pass re-reading and re-writing every byte at the end.
    ///
    /// Any part failing throws, and the caller falls back to a single-stream
    /// download — multi-part resume isn't supported, only fresh starts.
    ///
    /// Bytes land in a sibling `.dddownload` file that is renamed into place only
    /// once every range has completed. Writing directly to the final name would
    /// mean a download killed mid-flight (force quit, crash, power loss — the
    /// `catch` never runs) leaves a full-size file full of holes, and both the
    /// folder-resume skip check and the user would read it as finished.
    private func multiPartDownload(
        requestURL: URL,
        credential: DriveCredential,
        resourceKeys: [String: String],
        destinationURL: URL,
        totalBytes: Int64,
        onBytes: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let stagingURL = destinationURL.appendingPathExtension(Self.partialExtension)
        for url in [destinationURL, stagingURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        guard FileManager.default.createFile(atPath: stagingURL.path, contents: nil) else {
            throw DriveDownloadError.invalidResponse
        }

        do {
            // Give the file its full logical size so every range has somewhere to
            // land; APFS keeps it sparse until the bytes are actually written.
            let sizing = try FileHandle(forWritingTo: stagingURL)
            try sizing.truncate(atOffset: UInt64(totalBytes))
            try sizing.close()

            let ranges = Self.splitRanges(totalBytes: totalBytes, partCount: Self.multiPartCount(forSize: totalBytes))

            try await withThrowingTaskGroup(of: Void.self) { group in
                for range in ranges {
                    group.addTask {
                        var partRequest = URLRequest(url: requestURL)
                        credential.applying(to: &partRequest)
                        Self.applyResourceKeys(resourceKeys, to: &partRequest)
                        partRequest.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")

                        // One handle per range: each keeps its own file offset, so
                        // concurrent writes to different regions don't interfere.
                        let handle = try FileHandle(forWritingTo: stagingURL)
                        let coordinator = try RangedStreamCoordinator(
                            fileHandle: handle,
                            startOffset: UInt64(range.lowerBound),
                            expectedBytes: range.upperBound - range.lowerBound + 1,
                            onBytes: onBytes
                        )
                        let session = URLSession(configuration: .ephemeral, delegate: coordinator, delegateQueue: nil)
                        defer { session.finishTasksAndInvalidate() }
                        try await coordinator.run(session: session, request: partRequest)
                    }
                }
                try await group.waitForAll()
            }
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            throw error
        }

        // Same volume, so this is a rename — no second copy, no extra space.
        try FileManager.default.moveItem(at: stagingURL, to: destinationURL)
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

    /// Drive stores a file's type in its metadata, not necessarily in its name:
    /// a clip uploaded as "Vo" comes back named exactly "Vo", with the type only
    /// in `mimeType`. Written out under that bare name the download is complete
    /// and byte-perfect, but macOS has nothing to identify it by — Finder shows
    /// the blank "?" document and a double-click hands the raw bytes to TextEdit,
    /// which looks exactly like a corrupted file. So a name carrying no *usable*
    /// extension gets the one its declared type implies.
    ///
    /// "No usable one" is deliberately wider than "no dot in the name". Drive
    /// also hands back names like "ไฟล์ - 2026-08-10T05:03:42.549Z", where the
    /// trailing ".549Z" is part of a timestamp: macOS reads it as an extension,
    /// finds no type registered for it, and shows the same blank "?" document as
    /// a name with no dot at all.
    ///
    /// An extension that *does* map to a known type is left alone, mismatch with
    /// the declared type or not. The name is the one part of the file the person
    /// who uploaded it chose, and second-guessing a real ".mov" against a
    /// "video/mp4" label would only ever produce "clip.mov.mp4".
    private static func nameWithTypeExtension(_ name: String, mimeType: String) -> String {
        let sanitized = sanitizedName(name)
        // An extension nothing has registered doesn't come back as nil — the
        // system invents a dynamic "dyn.a…" type for it, which is exactly the
        // case being detected here, so nil and dynamic both count as unusable.
        let existing = UTType(filenameExtension: (sanitized as NSString).pathExtension)
        guard existing == nil || existing?.isDynamic == true,
              let fileExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension
        else { return sanitized }
        return "\(sanitized).\(fileExtension)"
    }

    /// `originalName` under a new base name, keeping the extension it already
    /// had. Typing "holiday" over "IMG_4021.HEIC" gives "holiday.HEIC" — the
    /// extension is what makes the file openable, so it is never the user's to
    /// delete by accident. A typed name that already ends in the right extension
    /// isn't given a second one.
    static func renamed(_ originalName: String, to newBaseName: String?) -> String {
        guard let newBaseName, !newBaseName.isEmpty else { return sanitizedName(originalName) }
        let fileExtension = (originalName as NSString).pathExtension
        guard !fileExtension.isEmpty else { return sanitizedName(newBaseName) }
        let sanitized = sanitizedName(newBaseName)
        // Compared case-insensitively on both sides: ".HEIC" typed over a ".HEIC"
        // file must not become "name.HEIC.HEIC".
        if sanitized.lowercased().hasSuffix(".\(fileExtension.lowercased())") { return sanitized }
        return "\(sanitized).\(fileExtension)"
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
        // Must stay in step with what downloadFile writes: this name is what the
        // folder plan checks for on disk to decide a file is already done.
        return nameWithTypeExtension(file.name, mimeType: file.mimeType)
    }

    /// Extension for a file still being written. Only the rename at the end
    /// publishes the real name, so anything left with this suffix is incomplete.
    static let partialExtension = "dddownload"

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

    /// Deletes the partially-downloaded folder a cancelled/removed queue item left
    /// behind. The folder may have been uniquified to "Name (1)" on creation, so
    /// every immediate subfolder of the destination is checked for this item's
    /// in-progress marker rather than reconstructing the name. Only a folder still
    /// carrying the marker is touched — a finished download had its marker cleared,
    /// and a folder the user made themselves never had one, so neither can ever be
    /// deleted here.
    static func removePartialFolderArtifact(itemID: String, in destinationURL: URL) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: destinationURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants]
        )) ?? []

        for candidate in contents {
            guard (try? candidate.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let marker = candidate.appendingPathComponent(resumeMarkerName)
            guard let ownerID = try? String(contentsOf: marker, encoding: .utf8), ownerID == itemID else { continue }
            try? FileManager.default.removeItem(at: candidate)
        }
    }

    /// Deletes the `.dddownload` staging file belonging to one specific item.
    ///
    /// Deliberately targeted rather than sweeping every `.dddownload` in the
    /// folder: cancelling or removing one queue item would otherwise delete the
    /// staging file of a *different* download that is still running into the
    /// same destination, which drops that download back to a single stream and
    /// throws away everything it had transferred.
    /// The staging file is "<final name>.dddownload", and the final name isn't
    /// always the Drive name the caller knows: an extension-less file gains one
    /// from its type. Matched by prefix for that reason — still scoped to this
    /// item's own name, so a different download running into the same folder is
    /// never touched.
    static func removePartialFile(named name: String, in folderURL: URL) {
        let base = sanitizedName(name)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]
        )) ?? []
        for url in contents
        where url.pathExtension == partialExtension && url.deletingPathExtension().lastPathComponent.hasPrefix(base) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Deletes leftover `.dddownload` staging files anywhere under a folder — a
    /// download killed mid-flight can't clean up after itself.
    private static func removePartialFiles(in folderURL: URL) {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator where url.pathExtension == partialExtension {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func writeResumeMarker(itemID: String, in folderURL: URL) {
        let marker = folderURL.appendingPathComponent(resumeMarkerName)
        try? itemID.write(to: marker, atomically: true, encoding: .utf8)
    }

    private static func clearResumeMarker(itemID: String, in folderURL: URL) {
        try? FileManager.default.removeItem(at: folderURL.appendingPathComponent(resumeMarkerName))
    }
}

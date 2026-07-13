import Foundation

protocol DownloadServicing {
    @discardableResult
    func download(_ request: DownloadRequest, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL
    func analyzeLink(itemID: String) async throws -> LinkAnalysisResult
    func clearAnalysisCache() async
}

struct DriveFile: Decodable {
    private struct Owner: Decodable {
        let displayName: String?
    }

    let id: String
    let name: String
    let mimeType: String
    let size: Int64?
    let ownerName: String?

    var isFolder: Bool { mimeType == "application/vnd.google-apps.folder" }

    private enum CodingKeys: String, CodingKey {
        case id, name, mimeType, size, owners
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

/// Either an OAuth bearer token (private, user-authorized access) or a project API key
/// (anonymous access to publicly-shared files/folders, no sign-in required).
private enum DriveCredential {
    case oauth(String)
    case apiKey(String)

    func applying(to components: inout URLComponents) {
        if case .apiKey(let key) = self {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "key", value: key))
            components.queryItems = items
        }
    }

    func applying(to request: inout URLRequest) {
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

private final class ProgressTracker {
    private(set) var completedFiles = 0
    let totalFiles: Int
    private(set) var bytesDownloaded: Int64 = 0
    let totalBytes: Int64
    private var lastSampleTime = Date()
    private var lastSampleBytes: Int64 = 0
    private var smoothedRate: Double = 0
    private var currentFileName = ""

    init(totalFiles: Int, totalBytes: Int64) {
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
    }

    func startingFile(_ name: String) -> DownloadProgress {
        currentFileName = name
        return snapshot()
    }

    func addingBytes(_ count: Int64) -> DownloadProgress {
        bytesDownloaded += count
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSampleTime)
        if elapsed >= 0.2 {
            let deltaBytes = bytesDownloaded - lastSampleBytes
            let instantRate = elapsed > 0 ? Double(deltaBytes) / elapsed : 0
            smoothedRate = smoothedRate == 0 ? instantRate : (smoothedRate * 0.7 + instantRate * 0.3)
            lastSampleTime = now
            lastSampleBytes = bytesDownloaded
        }
        return snapshot()
    }

    func completingFile() -> DownloadProgress {
        completedFiles += 1
        return snapshot()
    }

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

struct GoogleDriveDownloadService: DownloadServicing {
    private static let apiBase = "https://www.googleapis.com/drive/v3/files"
    private static let bufferSize = 1 << 16

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

    func analyzeLink(itemID: String) async throws -> LinkAnalysisResult {
        if let cached = await AnalysisCache.shared.get(itemID) {
            return cached
        }

        let result = try await performAnalysis(itemID: itemID)

        if case .success = result {
            await AnalysisCache.shared.set(itemID, result)
        }

        return result
    }

    private func performAnalysis(itemID: String) async throws -> LinkAnalysisResult {
        if let apiKey = Self.configuredAPIKey,
           let metadata = try? await fetchMetadata(fileID: itemID, credential: .apiKey(apiKey)) {
            let analysis = try await buildAnalysis(for: metadata, credential: .apiKey(apiKey), isPublic: true)
            return .success(analysis)
        }

        guard let token = await loginManager.cachedAccessTokenIfAvailable() else {
            return .needsAuthentication
        }

        let metadata = try await fetchMetadata(fileID: itemID, credential: .oauth(token))
        let analysis = try await buildAnalysis(for: metadata, credential: .oauth(token), isPublic: false)
        return .success(analysis)
    }

    private func buildAnalysis(for metadata: DriveFile, credential: DriveCredential, isPublic: Bool) async throws -> DriveLinkAnalysis {
        guard metadata.isFolder else {
            return DriveLinkAnalysis(
                itemID: metadata.id,
                name: metadata.name,
                type: .file,
                isPublic: isPublic,
                requiresAuthentication: !isPublic,
                totalBytes: metadata.size,
                fileCount: nil,
                ownerName: metadata.ownerName
            )
        }

        let (fileCount, totalBytes) = try await estimateFolderContents(folderID: metadata.id, credential: credential)
        return DriveLinkAnalysis(
            itemID: metadata.id,
            name: metadata.name,
            type: .folder,
            isPublic: isPublic,
            requiresAuthentication: !isPublic,
            totalBytes: totalBytes,
            fileCount: fileCount,
            ownerName: metadata.ownerName
        )
    }

    private func estimateFolderContents(folderID: String, credential: DriveCredential) async throws -> (fileCount: Int, totalBytes: Int64) {
        try Task.checkCancellation()
        let children = try await listChildren(of: folderID, credential: credential)
        var count = 0
        var bytes: Int64 = 0

        for child in children {
            if child.isFolder {
                let (childCount, childBytes) = try await estimateFolderContents(folderID: child.id, credential: credential)
                count += childCount
                bytes += childBytes
            } else if Self.isDownloadable(mimeType: child.mimeType) {
                count += 1
                bytes += child.size ?? 0
            }
        }

        return (count, bytes)
    }

    // MARK: - Download

    @discardableResult
    func download(_ request: DownloadRequest, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        let credential = try await resolveCredential(for: request.itemID)

        progress(DownloadProgress(currentFileName: "Reading details…"))
        let rootMetadata = try await fetchMetadata(fileID: request.itemID, credential: credential)

        guard rootMetadata.isFolder else {
            guard Self.isDownloadable(mimeType: rootMetadata.mimeType) else {
                throw DriveDownloadError.unsupportedFileType
            }

            progress(DownloadProgress(currentFileName: rootMetadata.name, totalFiles: 1, totalBytes: rootMetadata.size ?? 0))
            let tracker = ProgressTracker(totalFiles: 1, totalBytes: rootMetadata.size ?? 0)
            let fileURL = try await downloadFile(rootMetadata, into: request.destinationURL, credential: credential) { chunkSize in
                progress(tracker.addingBytes(chunkSize))
            }
            progress(tracker.completingFile())
            return fileURL
        }

        let rootFolderURL = request.destinationURL.appendingPathComponent(
            Self.sanitizedName(rootMetadata.name),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: rootFolderURL, withIntermediateDirectories: true)

        progress(DownloadProgress(currentFileName: "Scanning folder contents…"))
        let plan = try await enumerate(folderID: request.itemID, into: rootFolderURL, credential: credential)

        let totalBytes = plan.reduce(Int64(0)) { $0 + ($1.file.size ?? 0) }
        let tracker = ProgressTracker(totalFiles: plan.count, totalBytes: totalBytes)

        for item in plan {
            try Task.checkCancellation()
            progress(tracker.startingFile(item.file.name))
            try await downloadFile(item.file, into: item.destinationFolderURL, credential: credential) { chunkSize in
                progress(tracker.addingBytes(chunkSize))
            }
            progress(tracker.completingFile())
        }

        return rootFolderURL
    }

    /// Prefers anonymous API-key access when the item is publicly reachable; falls back
    /// to an authenticated OAuth token (prompting sign-in if necessary) otherwise.
    private func resolveCredential(for itemID: String) async throws -> DriveCredential {
        // Prior analysis already determined public/private for this item — reuse that
        // instead of re-probing anonymous access with another network round trip.
        if let apiKey = Self.configuredAPIKey,
           case .success(let analysis) = await AnalysisCache.shared.get(itemID),
           analysis.isPublic {
            return .apiKey(apiKey)
        }

        if await AnalysisCache.shared.get(itemID) == nil, let apiKey = Self.configuredAPIKey,
           (try? await fetchMetadata(fileID: itemID, credential: .apiKey(apiKey))) != nil {
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
        credential: DriveCredential
    ) async throws -> [PlanItem] {
        try Task.checkCancellation()
        let children = try await listChildren(of: folderID, credential: credential)
        var items: [PlanItem] = []

        for child in children {
            if child.isFolder {
                let childURL = localFolderURL.appendingPathComponent(Self.sanitizedName(child.name), isDirectory: true)
                try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
                items.append(contentsOf: try await enumerate(folderID: child.id, into: childURL, credential: credential))
            } else if Self.isDownloadable(mimeType: child.mimeType) {
                items.append(PlanItem(file: child, destinationFolderURL: localFolderURL))
            }
        }

        return items
    }

    private func fetchMetadata(fileID: String, credential: DriveCredential) async throws -> DriveFile {
        var components = URLComponents(string: "\(Self.apiBase)/\(fileID)")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "id,name,mimeType,size,owners(displayName)"),
            URLQueryItem(name: "supportsAllDrives", value: "true")
        ]
        credential.applying(to: &components)

        var request = URLRequest(url: components.url!)
        credential.applying(to: &request)

        let (data, response) = try await urlSession.data(for: request)
        try Self.validate(response, data: data)
        return try JSONDecoder().decode(DriveFile.self, from: data)
    }

    private func listChildren(of folderID: String, credential: DriveCredential) async throws -> [DriveFile] {
        var files: [DriveFile] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(string: Self.apiBase)!
            var queryItems = [
                URLQueryItem(name: "q", value: "'\(folderID)' in parents and trashed = false"),
                URLQueryItem(name: "fields", value: "nextPageToken, files(id, name, mimeType, size)"),
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

            let (data, response) = try await urlSession.data(for: request)
            try Self.validate(response, data: data)

            let decoded = try JSONDecoder().decode(DriveListResponse.self, from: data)
            files.append(contentsOf: decoded.files)
            pageToken = decoded.nextPageToken
        } while pageToken != nil

        return files
    }

    @discardableResult
    private func downloadFile(
        _ file: DriveFile,
        into folderURL: URL,
        credential: DriveCredential,
        onBytes: @escaping (Int64) -> Void
    ) async throws -> URL {
        let destinationURL: URL
        let requestURL: URL

        if let export = Self.exportMimeTypes[file.mimeType] {
            destinationURL = folderURL.appendingPathComponent(
                Self.fileName(file.name, withExtension: export.fileExtension)
            )
            var components = URLComponents(string: "\(Self.apiBase)/\(file.id)/export")!
            components.queryItems = [URLQueryItem(name: "mimeType", value: export.mimeType)]
            credential.applying(to: &components)
            requestURL = components.url!
        } else {
            destinationURL = folderURL.appendingPathComponent(Self.sanitizedName(file.name))
            var components = URLComponents(string: "\(Self.apiBase)/\(file.id)")!
            components.queryItems = [
                URLQueryItem(name: "alt", value: "media"),
                URLQueryItem(name: "supportsAllDrives", value: "true")
            ]
            credential.applying(to: &components)
            requestURL = components.url!
        }

        var request = URLRequest(url: requestURL)
        credential.applying(to: &request)

        let (byteStream, response) = try await urlSession.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DriveDownloadError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in byteStream {
                errorData.append(byte)
            }
            let message = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw DriveDownloadError.server(httpResponse.statusCode, message)
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: destinationURL)

        do {
            var buffer = Data()
            buffer.reserveCapacity(Self.bufferSize)

            for try await byte in byteStream {
                buffer.append(byte)
                if buffer.count >= Self.bufferSize {
                    try Task.checkCancellation()
                    try fileHandle.write(contentsOf: buffer)
                    onBytes(Int64(buffer.count))
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            if !buffer.isEmpty {
                try fileHandle.write(contentsOf: buffer)
                onBytes(Int64(buffer.count))
            }

            try fileHandle.close()
        } catch {
            try? fileHandle.close()
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }

        return destinationURL
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
}

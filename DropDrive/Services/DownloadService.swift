import Foundation

protocol DownloadServicing {
    @discardableResult
    func download(_ request: DownloadRequest, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL
}

struct DriveFile: Decodable {
    let id: String
    let name: String
    let mimeType: String
    let size: Int64?

    var isFolder: Bool { mimeType == "application/vnd.google-apps.folder" }

    private enum CodingKeys: String, CodingKey {
        case id, name, mimeType, size
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
    }
}

private struct DriveListResponse: Decodable {
    let files: [DriveFile]
    let nextPageToken: String?
}

enum DriveDownloadError: LocalizedError {
    case invalidResponse
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Received an unexpected response from Google Drive."
        case .server(let statusCode, let message):
            "Google Drive returned an error (\(statusCode)): \(message)"
        }
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

    private let loginManager: LoginManaging
    private let urlSession: URLSession

    init(loginManager: LoginManaging, urlSession: URLSession = .shared) {
        self.loginManager = loginManager
        self.urlSession = urlSession
    }

    @discardableResult
    func download(_ request: DownloadRequest, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        let accessToken = try await loginManager.validAccessToken()

        progress(DownloadProgress(currentFileName: "Reading folder details…"))
        let rootMetadata = try await fetchMetadata(fileID: request.folderID, accessToken: accessToken)

        let rootFolderURL = request.destinationURL.appendingPathComponent(
            Self.sanitizedName(rootMetadata.name),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: rootFolderURL, withIntermediateDirectories: true)

        progress(DownloadProgress(currentFileName: "Scanning folder contents…"))
        let plan = try await enumerate(folderID: request.folderID, into: rootFolderURL, accessToken: accessToken)

        let totalBytes = plan.reduce(Int64(0)) { $0 + ($1.file.size ?? 0) }
        let tracker = ProgressTracker(totalFiles: plan.count, totalBytes: totalBytes)

        for item in plan {
            try Task.checkCancellation()
            progress(tracker.startingFile(item.file.name))
            try await downloadFile(item.file, into: item.destinationFolderURL, accessToken: accessToken) { chunkSize in
                progress(tracker.addingBytes(chunkSize))
            }
            progress(tracker.completingFile())
        }

        return rootFolderURL
    }

    private struct PlanItem {
        let file: DriveFile
        let destinationFolderURL: URL
    }

    private func enumerate(
        folderID: String,
        into localFolderURL: URL,
        accessToken: String
    ) async throws -> [PlanItem] {
        try Task.checkCancellation()
        let children = try await listChildren(of: folderID, accessToken: accessToken)
        var items: [PlanItem] = []

        for child in children {
            if child.isFolder {
                let childURL = localFolderURL.appendingPathComponent(Self.sanitizedName(child.name), isDirectory: true)
                try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
                items.append(contentsOf: try await enumerate(folderID: child.id, into: childURL, accessToken: accessToken))
            } else if Self.exportMimeTypes[child.mimeType] != nil || !child.mimeType.hasPrefix("application/vnd.google-apps.") {
                items.append(PlanItem(file: child, destinationFolderURL: localFolderURL))
            }
        }

        return items
    }

    private func fetchMetadata(fileID: String, accessToken: String) async throws -> DriveFile {
        var components = URLComponents(string: "\(Self.apiBase)/\(fileID)")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "id,name,mimeType,size"),
            URLQueryItem(name: "supportsAllDrives", value: "true")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        try Self.validate(response, data: data)
        return try JSONDecoder().decode(DriveFile.self, from: data)
    }

    private func listChildren(of folderID: String, accessToken: String) async throws -> [DriveFile] {
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

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await urlSession.data(for: request)
            try Self.validate(response, data: data)

            let decoded = try JSONDecoder().decode(DriveListResponse.self, from: data)
            files.append(contentsOf: decoded.files)
            pageToken = decoded.nextPageToken
        } while pageToken != nil

        return files
    }

    private func downloadFile(
        _ file: DriveFile,
        into folderURL: URL,
        accessToken: String,
        onBytes: @escaping (Int64) -> Void
    ) async throws {
        let destinationURL: URL
        let requestURL: URL

        if let export = Self.exportMimeTypes[file.mimeType] {
            destinationURL = folderURL.appendingPathComponent(
                Self.fileName(file.name, withExtension: export.fileExtension)
            )
            var components = URLComponents(string: "\(Self.apiBase)/\(file.id)/export")!
            components.queryItems = [URLQueryItem(name: "mimeType", value: export.mimeType)]
            requestURL = components.url!
        } else {
            destinationURL = folderURL.appendingPathComponent(Self.sanitizedName(file.name))
            var components = URLComponents(string: "\(Self.apiBase)/\(file.id)")!
            components.queryItems = [
                URLQueryItem(name: "alt", value: "media"),
                URLQueryItem(name: "supportsAllDrives", value: "true")
            ]
            requestURL = components.url!
        }

        var request = URLRequest(url: requestURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

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

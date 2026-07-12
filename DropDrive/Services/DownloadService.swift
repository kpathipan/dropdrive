import Foundation

protocol DownloadServicing {
    func download(_ request: DownloadRequest, progress: @escaping @Sendable (String) -> Void) async throws
}

struct DriveFile: Decodable {
    let id: String
    let name: String
    let mimeType: String

    var isFolder: Bool { mimeType == "application/vnd.google-apps.folder" }
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

struct GoogleDriveDownloadService: DownloadServicing {
    private static let apiBase = "https://www.googleapis.com/drive/v3/files"

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

    func download(_ request: DownloadRequest, progress: @escaping @Sendable (String) -> Void) async throws {
        let accessToken = try await loginManager.validAccessToken()

        progress("Reading folder details...")
        let rootMetadata = try await fetchMetadata(fileID: request.folderID, accessToken: accessToken)

        let rootFolderURL = request.destinationURL.appendingPathComponent(
            Self.sanitizedName(rootMetadata.name),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: rootFolderURL, withIntermediateDirectories: true)

        try await downloadContents(
            ofFolderID: request.folderID,
            into: rootFolderURL,
            accessToken: accessToken,
            progress: progress
        )

        progress("Download complete.")
    }

    private func downloadContents(
        ofFolderID folderID: String,
        into localFolderURL: URL,
        accessToken: String,
        progress: @escaping @Sendable (String) -> Void
    ) async throws {
        let children = try await listChildren(of: folderID, accessToken: accessToken)

        for child in children {
            let childName = Self.sanitizedName(child.name)

            if child.isFolder {
                let childURL = localFolderURL.appendingPathComponent(childName, isDirectory: true)
                try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
                try await downloadContents(
                    ofFolderID: child.id,
                    into: childURL,
                    accessToken: accessToken,
                    progress: progress
                )
            } else {
                progress("Downloading \(child.name)...")
                try await downloadFile(child, into: localFolderURL, accessToken: accessToken)
            }
        }
    }

    private func fetchMetadata(fileID: String, accessToken: String) async throws -> DriveFile {
        var components = URLComponents(string: "\(Self.apiBase)/\(fileID)")!
        components.queryItems = [URLQueryItem(name: "fields", value: "id,name,mimeType")]

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
                URLQueryItem(name: "fields", value: "nextPageToken, files(id, name, mimeType)"),
                URLQueryItem(name: "pageSize", value: "1000"),
                URLQueryItem(name: "supportsAllDrives", value: "true"),
                URLQueryItem(name: "includeItemsFromAllDrives", value: "true")
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

    private func downloadFile(_ file: DriveFile, into folderURL: URL, accessToken: String) async throws {
        let destinationURL: URL
        let requestURL: URL

        if let export = Self.exportMimeTypes[file.mimeType] {
            destinationURL = folderURL.appendingPathComponent(
                Self.fileName(file.name, withExtension: export.fileExtension)
            )
            var components = URLComponents(string: "\(Self.apiBase)/\(file.id)/export")!
            components.queryItems = [URLQueryItem(name: "mimeType", value: export.mimeType)]
            requestURL = components.url!
        } else if file.mimeType.hasPrefix("application/vnd.google-apps.") {
            return
        } else {
            destinationURL = folderURL.appendingPathComponent(Self.sanitizedName(file.name))
            var components = URLComponents(string: "\(Self.apiBase)/\(file.id)")!
            components.queryItems = [URLQueryItem(name: "alt", value: "media")]
            requestURL = components.url!
        }

        var request = URLRequest(url: requestURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (tempURL, response) = try await urlSession.download(for: request)

        do {
            try Self.validate(response, data: try? Data(contentsOf: tempURL))
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
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

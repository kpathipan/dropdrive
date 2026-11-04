import Foundation
import UniformTypeIdentifiers

nonisolated struct UploadFolderPage: Sendable {
    let folders: [UploadFolder]
    let nextPageToken: String?
}

nonisolated struct UploadRemoteFile: Codable, Sendable {
    let id: String
    let name: String
    let mimeType: String?
    let size: String?
    let md5Checksum: String?
    let parents: [String]?
    let driveId: String?
    let trashed: Bool?
    let capabilities: Capabilities?
    nonisolated struct Capabilities: Codable, Sendable { let canAddChildren: Bool? }
}

nonisolated final class UploadNetworkDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let progress: @Sendable (Int64) -> Void
    init(progress: @escaping @Sendable (Int64) -> Void = { _ in }) { self.progress = progress }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) { progress(totalBytesSent) }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Credentials and resumable capabilities must never follow a redirect.
        completionHandler(nil)
    }
}

/// The UI and MCP both call this engine. Uses bounded chunks, a server-generated
/// durable file ID, exact-account tokens, and independent metadata verification.
actor DriveUploadEngine {
    typealias Tokens = @Sendable (_ accountID: String, _ forceRefresh: Bool) async throws -> GoogleAccessToken
    typealias Checkpoint = @Sendable (PrivateUploadRecord) async throws -> Void
    typealias Progress = @Sendable (Int64) async -> Void
    private let tokens: Tokens
    private let session: URLSession
    static let fields = "id,name,mimeType,size,md5Checksum,parents,driveId,trashed,capabilities(canAddChildren)"
    private static let folderMIME = "application/vnd.google-apps.folder"
    private static let chunkSize = 8 * 1_048_576 // 256 KiB multiple; memory bound, not a file-size limit.

    init(session: URLSession? = nil, tokens: @escaping Tokens = { account, refresh in
        try await LoginManager.shared.uploadAccessToken(accountID: account, forceRefresh: refresh)
    }) {
        self.tokens = tokens
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 120; config.timeoutIntervalForResource = 600
        self.session = session ?? URLSession(configuration: config, delegate: UploadNetworkDelegate(), delegateQueue: nil)
    }

    private func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL {
        var url = URLComponents(string: "https://www.googleapis.com/" + path)!
        url.queryItems = query; return url.url!
    }

    private func send(_ request: URLRequest, account: String, body: Data? = nil,
                      progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws -> (Data, HTTPURLResponse) {
        for refreshed in [false, true] {
            try Task.checkCancellation()
            var signed = request
            let token = try await tokens(account, refreshed)
            guard token.accountID == account else { throw AutomationFailure("account_mismatch", "Upload account changed unexpectedly.") }
            signed.setValue("Bearer \(token.token)", forHTTPHeaderField: "Authorization")
            let data: Data, response: URLResponse
            do {
                if let body {
                    (data, response) = try await session.upload(for: signed, from: body, delegate: UploadNetworkDelegate(progress: progress))
                } else { (data, response) = try await session.data(for: signed) }
            } catch is CancellationError { throw CancellationError() }
            catch {
                if Task.isCancelled { throw CancellationError() }
                // Never propagate URLSession's URL-bearing localizedDescription.
                throw AutomationFailure("network_error", "Upload connection interrupted. Retry resumes using the same Drive file ID.")
            }
            guard let http = response as? HTTPURLResponse else { throw AutomationFailure("invalid_response", "Drive returned an invalid response.") }
            if http.statusCode == 401 && !refreshed { continue }
            return (data, http)
        }
        throw AutomationFailure("authentication_required", "Reconnect the upload account in DropDrive.")
    }

    private func failure(_ status: Int, data: Data) -> AutomationFailure {
        let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = parsed?["error"] as? [String: Any]
        let reason = (error?["errors"] as? [[String: Any]])?.first?["reason"] as? String ?? ""
        switch (status, reason) {
        case (401, _): return AutomationFailure("authentication_required", "Reconnect this Google account in DropDrive.")
        case (_, "storageQuotaExceeded"), (_, "teamDriveFileLimitExceeded"), (_, "activeItemCreationLimitExceeded"):
            return AutomationFailure("drive_quota_exceeded", "Drive storage or item quota is exhausted. Free space or choose another permitted folder.")
        case (_, "rateLimitExceeded"), (_, "userRateLimitExceeded"), (429, _):
            return AutomationFailure("rate_limited", "Google Drive is rate limiting uploads. Wait, then retry the same job.")
        case (_, "dailyLimitExceeded"), (_, "uploadLimitExceeded"):
            return AutomationFailure("drive_quota_exceeded", "Google Drive's upload/API quota is exhausted. Wait for the quota to reset or ask your administrator, then retry the same job.")
        case (403, _): return AutomationFailure("folder_not_authorized", "Drive denied this upload. Check folder write access and organization policy; if required, select the folder with Google Picker. No broader Drive permission was requested.")
        case (404, _): return AutomationFailure("folder_not_authorized", "Folder is missing or not authorized for this app/account. Select an accessible folder in DropDrive.")
        case (409, _): return AutomationFailure("remote_conflict", "This Drive file ID already exists. Verify it before retrying.")
        case (500...599, _): return AutomationFailure("server_error", "Google Drive is temporarily unavailable. Retry resumes this job.")
        default: return AutomationFailure("drive_error", "Google Drive rejected the operation (HTTP \(status)).")
        }
    }

    private func json(_ path: String, account: String, query: [URLQueryItem] = [], method: String = "GET", value: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: endpoint(path, query: query)); request.httpMethod = method
        if let value {
            request.httpBody = try JSONSerialization.data(withJSONObject: value)
            request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await send(request, account: account)
        guard (200..<300).contains(response.statusCode) else { throw failure(response.statusCode, data: data) }
        return data
    }

    func metadata(id: String, account: String) async throws -> UploadRemoteFile {
        let data = try await json("drive/v3/files/\(id)", account: account,
            query: [.init(name: "supportsAllDrives", value: "true"), .init(name: "fields", value: Self.fields)])
        return try JSONDecoder().decode(UploadRemoteFile.self, from: data)
    }

    func folder(_ input: String, account: String) async throws -> UploadFolder {
        let id = try UploadInput.folderID(input)
        let file = try await metadata(id: id, account: account)
        guard file.mimeType == Self.folderMIME, file.trashed != true else {
            throw AutomationFailure("invalid_folder", "Choose an existing Google Drive folder.")
        }
        var names = [file.name], parent = file.parents?.first, seen: Set<String> = [file.id]
        // Only ancestors of the selected folder; never enumerate unrelated files.
        for _ in 0..<50 {
            guard let current = parent, seen.insert(current).inserted else { break }
            guard let ancestor = try? await metadata(id: current, account: account) else { break }
            names.insert(ancestor.name, at: 0); parent = ancestor.parents?.first
        }
        return UploadFolder(id: file.id, name: file.name, path: names.joined(separator: " / "), accountID: account,
                            driveID: file.driveId, canUpload: file.capabilities?.canAddChildren == true)
    }

    private func escape(_ value: String) -> String { value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") }

    func folders(parent: String?, pageToken: String?, account: String) async throws -> UploadFolderPage {
        var query = [URLQueryItem(name: "q", value: "trashed=false and mimeType='\(Self.folderMIME)'" + (parent.map { " and '\(escape($0))' in parents" } ?? "")),
                     .init(name: "supportsAllDrives", value: "true"), .init(name: "includeItemsFromAllDrives", value: "true"),
                     .init(name: "pageSize", value: "100"), .init(name: "orderBy", value: "name"),
                     .init(name: "fields", value: "nextPageToken,incompleteSearch,files(\(Self.fields))")]
        if let pageToken { query.append(.init(name: "pageToken", value: pageToken)) }
        struct Page: Decodable { let files: [UploadRemoteFile]; let nextPageToken: String?; let incompleteSearch: Bool? }
        let page = try JSONDecoder().decode(Page.self, from: await json("drive/v3/files", account: account, query: query))
        return UploadFolderPage(folders: page.files.map { UploadFolder(id: $0.id, name: $0.name, path: $0.name,
            accountID: account, driveID: $0.driveId, canUpload: $0.capabilities?.canAddChildren == true) }, nextPageToken: page.nextPageToken)
    }

    func generatedID(account: String) async throws -> String {
        struct IDs: Decodable { let ids: [String] }
        let data = try await json("drive/v3/files/generateIds", account: account, query: [.init(name: "count", value: "1"), .init(name: "space", value: "drive"), .init(name: "type", value: "files")])
        guard let id = try JSONDecoder().decode(IDs.self, from: data).ids.first else { throw AutomationFailure("invalid_response", "Drive did not return a file ID.") }
        return id
    }

    func createFolder(id: String, name: String, parent: String, account: String) async throws -> UploadFolder {
        try UploadInput.validateName(name)
        let parentID = try UploadInput.folderID(parent)
        if let existing = try? await metadata(id: id, account: account) {
            guard existing.name == name, existing.mimeType == Self.folderMIME, existing.trashed != true else {
                throw AutomationFailure("remote_conflict", "The stored folder ID refers to a different item. No existing item was changed.")
            }
            return try await folder(id, account: account)
        }
        let parentMetadata = try? await metadata(id: parentID, account: account)
        let target = UploadFolder(id: parentID, name: parentMetadata?.name ?? "My Drive", path: parentMetadata?.name ?? "My Drive",
                                  accountID: account, driveID: parentMetadata?.driveId, canUpload: true)
        if try await collision(folder: target, name: name, excluding: id) {
            throw AutomationFailure("name_conflict", "A folder or file with this name already exists here. Choose another name or select the existing folder.")
        }
        do {
            _ = try await json("drive/v3/files", account: account,
                query: [.init(name: "supportsAllDrives", value: "true"), .init(name: "fields", value: Self.fields)], method: "POST",
                value: ["id": id, "name": name, "mimeType": Self.folderMIME, "parents": [parentID]])
        } catch let error as AutomationFailure where error.code == "remote_conflict" {
            let existing = try await metadata(id: id, account: account)
            guard existing.name == name, existing.mimeType == Self.folderMIME else { throw error }
        }
        return try await folder(id, account: account)
    }

    private func collision(folder: UploadFolder, name: String, excluding: String?) async throws -> Bool {
        var query = [URLQueryItem(name: "q", value: "trashed=false and '\(escape(folder.id))' in parents and name='\(escape(name))'"),
                     .init(name: "fields", value: "files(id),nextPageToken,incompleteSearch"), .init(name: "pageSize", value: "100"),
                     .init(name: "supportsAllDrives", value: "true"), .init(name: "includeItemsFromAllDrives", value: "true")]
        if let drive = folder.driveID { query += [.init(name: "corpora", value: "drive"), .init(name: "driveId", value: drive)] }
        struct Entry: Decodable { let id: String }
        struct Page: Decodable { let files: [Entry]; let nextPageToken: String?; let incompleteSearch: Bool? }
        let data = try await json("drive/v3/files", account: folder.accountID, query: query)
        let page = try JSONDecoder().decode(Page.self, from: data)
        guard page.incompleteSearch != true, page.nextPageToken == nil else {
            throw AutomationFailure("collision_check_incomplete", "Drive could not complete the name check. Retry before uploading.")
        }
        return page.files.contains { $0.id != excluding }
    }

    private func validSession(_ value: String) throws -> URL {
        guard let components = URLComponents(string: value), components.scheme == "https",
              components.host == "www.googleapis.com", components.port == nil,
              components.user == nil, components.password == nil,
              components.path == "/upload/drive/v3/files" else {
            throw AutomationFailure("invalid_session", "Drive returned an unexpected resumable endpoint.")
        }
        return components.url!
    }

    func verify(_ record: PrivateUploadRecord) async throws -> UploadRemoteFile {
        guard let id = record.fileID, let account = record.job.upload?.folder?.accountID,
              account == record.accountID, let hash = record.sourceMD5, let source = record.sourceIdentity else {
            throw AutomationFailure("upload_not_verified", "No complete upload checkpoint exists for this job.")
        }
        let file = try await metadata(id: id, account: account)
        guard file.id == id, file.name == record.effectiveName, file.trashed != true,
              file.parents?.contains(record.job.upload!.folder!.id) == true,
              Int64(file.size ?? "") == source.size, file.md5Checksum?.lowercased() == hash else {
            throw AutomationFailure("integrity_mismatch", "Drive file name, folder, size or MD5 does not match the source. The job is not verified.")
        }
        return file
    }

    func run(_ initial: PrivateUploadRecord, checkpoint: @escaping Checkpoint, progress: @escaping Progress) async throws -> PrivateUploadRecord {
        var record = initial
        guard let path = record.job.command.sourcePath,
              let destination = record.job.command.driveFolder else { throw AutomationFailure("invalid_request", "Missing upload input.") }
        let account = record.accountID
        let source = try UploadSource(path: path)
        if let original = record.sourceIdentity, original != source.identity { throw AutomationFailure("source_changed", "Source changed since this job was created. Submit it as a new job.") }
        record.sourceIdentity = source.identity
        record.job.upload = record.job.upload ?? UploadStatus()
        record.job.upload!.totalBytes = source.identity.size
        record.job.state = "hashing"; try await checkpoint(record)
        // The checksum is streamed in bounded memory and never creates a source copy.
        let md5 = try source.md5()
        if let old = record.sourceMD5, old != md5 { throw AutomationFailure("source_changed", "Source content changed. Submit a new job.") }
        record.sourceMD5 = md5
        let selected = try await folder(destination, account: account)
        guard selected.canUpload else { throw AutomationFailure("folder_read_only", "This account cannot add files to the selected folder.") }
        record.job.upload!.folder = selected
        record.job.state = "preparing"; try await checkpoint(record)
        if record.fileID != nil, let _ = try? await verify(record) {
            return try await completed(record, checkpoint: checkpoint)
        }
        if record.sessionURL == nil, try await collision(folder: selected, name: record.effectiveName, excluding: record.fileID) {
            throw AutomationFailure("name_conflict", "A file with this name already exists in this folder. Choose a different name or cancel. Nothing was overwritten.")
        }
        if record.fileID == nil {
            record.fileID = try await generatedID(account: account)
            record.job.upload!.remoteFileID = record.fileID
            try await checkpoint(record) // MUST precede any create/upload HTTP request.
        }
        let mime = UTType(filenameExtension: URL(fileURLWithPath: path).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        var retries = 0
        while true {
            try Task.checkCancellation(); try source.checkUnchanged()
            do {
                if record.sessionURL == nil {
                    if try await collision(folder: selected, name: record.effectiveName, excluding: record.fileID) {
                        throw AutomationFailure("name_conflict", "This filename already exists. Rename or cancel this upload.")
                    }
                    var request = URLRequest(url: endpoint("upload/drive/v3/files", query: [.init(name: "uploadType", value: "resumable"), .init(name: "supportsAllDrives", value: "true"), .init(name: "fields", value: Self.fields)]))
                    request.httpMethod = "POST"
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["id": record.fileID!, "name": record.effectiveName, "parents": [selected.id], "mimeType": mime])
                    request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                    request.setValue(mime, forHTTPHeaderField: "X-Upload-Content-Type")
                    request.setValue(String(source.identity.size), forHTTPHeaderField: "X-Upload-Content-Length")
                    let (data, response) = try await send(request, account: account)
                    if response.statusCode == 409 { return try await completed(record, checkpoint: checkpoint) }
                    guard (200..<300).contains(response.statusCode), let location = response.value(forHTTPHeaderField: "Location") else {
                        throw failure(response.statusCode, data: data)
                    }
                    _ = try validSession(location)
                    record.sessionURL = location; record.confirmedOffset = 0
                    try await checkpoint(record)
                }
                // Probe before sending: the previous response may have been lost.
                var probe = URLRequest(url: try validSession(record.sessionURL!)); probe.httpMethod = "PUT"
                probe.setValue("bytes */\(source.identity.size)", forHTTPHeaderField: "Content-Range")
                let (probeData, probeResponse) = try await send(probe, account: account, body: Data())
                if [200, 201].contains(probeResponse.statusCode) { return try await completed(record, checkpoint: checkpoint) }
                if [404, 410].contains(probeResponse.statusCode) {
                    if let _ = try? await verify(record) { return try await completed(record, checkpoint: checkpoint) }
                    record.sessionURL = nil; record.confirmedOffset = 0; try await checkpoint(record)
                    retries += 1
                    guard retries <= 5 else { throw AutomationFailure("session_expired", "The Drive upload session expired. Retry this same job to keep its file ID.") }
                    continue
                }
                guard probeResponse.statusCode == 308 else { throw failure(probeResponse.statusCode, data: probeData) }
                record.confirmedOffset = try Self.offset(probeResponse, total: source.identity.size)
                record.job.state = "uploading"; record.job.upload!.bytesUploaded = record.confirmedOffset
                record.job.upload!.nextRetryAt = nil; try await checkpoint(record)
                repeat {
                    try Task.checkCancellation()
                    let offset = record.confirmedOffset
                    let chunk = try source.read(offset: offset, count: Self.chunkSize)
                    var request = URLRequest(url: try validSession(record.sessionURL!)); request.httpMethod = "PUT"
                    request.setValue(mime, forHTTPHeaderField: "Content-Type")
                    request.setValue(source.identity.size == 0 ? "bytes */0" : "bytes \(offset)-\(offset + Int64(chunk.count) - 1)/\(source.identity.size)", forHTTPHeaderField: "Content-Range")
                    let (data, response) = try await send(request, account: account, body: chunk) { sent in
                        Task { await progress(min(source.identity.size, offset + sent)) }
                    }
                    if [200, 201].contains(response.statusCode) {
                        try source.checkUnchanged()
                        return try await completed(record, checkpoint: checkpoint)
                    }
                    if [404, 410].contains(response.statusCode) { throw AutomationFailure("session_retry", "Upload session needs recovery.") }
                    guard response.statusCode == 308 else { throw failure(response.statusCode, data: data) }
                    let acknowledged = try Self.offset(response, total: source.identity.size)
                    guard acknowledged > offset, acknowledged <= offset + Int64(chunk.count) else {
                        throw AutomationFailure("invalid_response", "Drive acknowledged an invalid upload range.")
                    }
                    record.confirmedOffset = acknowledged; record.job.upload!.bytesUploaded = acknowledged
                    try await checkpoint(record); await progress(acknowledged)
                } while record.confirmedOffset < source.identity.size
                throw AutomationFailure("upload_not_verified", "Drive has all bytes but has not confirmed completion. Retry the same job to verify.")
            } catch let error as AutomationFailure where ["network_error", "server_error", "rate_limited", "session_retry"].contains(error.code) {
                retries += 1
                guard retries <= 5 else { throw error }
                record.job.state = "retrying"; record.job.upload!.retryCount += 1
                let delay = min(32, 1 << retries)
                record.job.upload!.nextRetryAt = .now.addingTimeInterval(Double(delay))
                record.job.message = error.message; try await checkpoint(record)
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func completed(_ initial: PrivateUploadRecord, checkpoint: Checkpoint) async throws -> PrivateUploadRecord {
        var record = initial
        record.job.state = "verifying"; try await checkpoint(record)
        let remote = try await verify(record)
        record.job.state = "completed"; record.job.errorCode = nil; record.job.message = nil
        record.job.upload!.verified = true; record.job.upload!.md5Checksum = remote.md5Checksum
        record.job.upload!.remoteFileID = remote.id
        record.job.upload!.remoteURL = "https://drive.google.com/file/d/\(remote.id)/view"
        record.job.upload!.bytesUploaded = record.sourceIdentity!.size
        record.job.upload!.nextRetryAt = nil; record.sessionURL = nil
        try await checkpoint(record); return record
    }

    static func offset(_ response: HTTPURLResponse, total: Int64) throws -> Int64 {
        guard let range = response.value(forHTTPHeaderField: "Range") else { return 0 }
        guard range.hasPrefix("bytes=0-"), let end = Int64(range.dropFirst(8)), end >= 0, end < total else {
            throw AutomationFailure("invalid_response", "Drive returned an invalid acknowledged range.")
        }
        return end + 1
    }
}

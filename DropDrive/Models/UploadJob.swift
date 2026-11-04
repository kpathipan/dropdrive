import Foundation

nonisolated struct UploadFolder: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    var path: String
    let accountID: String
    var driveID: String?
    var canUpload: Bool
}

/// The only upload representation allowed across IPC. Never add credentials or
/// resumable session URLs here; those belong exclusively to PrivateUploadRecord.
nonisolated struct UploadStatus: Codable, Equatable, Sendable {
    var bytesUploaded: Int64 = 0
    var totalBytes: Int64 = 0
    var remoteFileID: String?
    var remoteURL: String?
    var md5Checksum: String?
    var verified = false
    var retryCount = 0
    var nextRetryAt: Date?
    var folder: UploadFolder?
}

nonisolated struct UploadSourceIdentity: Codable, Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanos: Int64
}

/// App-private checkpoint. This type must never be encoded into an IPC reply.
nonisolated struct PrivateUploadRecord: Codable, Sendable {
    var job: AutomationJob
    var effectiveName: String
    var accountID: String
    var sourceIdentity: UploadSourceIdentity?
    var sourceMD5: String?
    var fileID: String?
    var sessionURL: String?
    var confirmedOffset: Int64 = 0
    var sourceBookmark: Data?
}

nonisolated enum UploadInput {
    static func folderID(_ value: String) throws -> String {
        if value == "root" { return value }
        var candidate = value
        if value.contains("://") {
            guard let parts = URLComponents(string: value), parts.scheme == "https",
                  parts.host == "drive.google.com", parts.user == nil, parts.password == nil,
                  let marker = parts.path.range(of: "/folders/") else {
                throw AutomationFailure("invalid_folder", "Use a Google Drive folder link or folder ID.")
            }
            candidate = String(parts.path[marker.upperBound...].prefix(while: { $0 != "/" }))
        }
        guard !candidate.isEmpty, candidate.utf8.count <= 256,
              candidate.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            throw AutomationFailure("invalid_folder", "Invalid Google Drive folder ID.")
        }
        return candidate
    }

    static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.utf16.count <= 255, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AutomationFailure("invalid_name", "Choose a single filename without slashes or control characters (up to 255 UTF-16 characters).")
        }
    }
}

import Foundation

nonisolated struct AutomationCommand: Codable, Equatable, Sendable {
    var protocolVersion: Int = 1
    let id: UUID
    let action: String
    var url: String?
    var name: String?
    var destination: String?
    var asAudio: Bool?
    var allowDuplicate: Bool?
    var jobID: UUID?

    func validate() throws {
        guard protocolVersion == 1 else { throw AutomationFailure("unsupported_version", "Expected protocol version 1.") }
        guard ["ping", "analyze", "download", "status"].contains(action) else {
            throw AutomationFailure("unsupported_action", "Unsupported command.")
        }
        if action == "status", jobID == nil { throw AutomationFailure("invalid_request", "jobID is required.") }
        guard action == "analyze" || action == "download" else { return }
        guard let url, url.count <= 8192, let parsed = URLComponents(string: url),
              parsed.scheme == "https", parsed.user == nil, parsed.password == nil,
              let host = parsed.host?.lowercased() else {
            throw AutomationFailure("invalid_link", "An HTTPS source link is required.")
        }
        let domains = ["drive.google.com", "docs.google.com", "youtube.com", "youtu.be", "tiktok.com", "instagram.com", "facebook.com", "fb.watch"]
        guard domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else {
            throw AutomationFailure("unsupported_link", "Use a supported Drive or video website link.")
        }
        if let name {
            guard !name.isEmpty, name.utf8.count <= 200, name != ".", name != "..",
                  !name.contains("/"), !name.contains("\\"), !name.contains(":"),
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw AutomationFailure("invalid_name", "Name must be a single safe filename or folder name.")
            }
        }
        if action == "download" {
            guard let destination, destination.hasPrefix("/"), !destination.contains("\0") else {
                throw AutomationFailure("invalid_destination", "Provide an absolute existing destination directory.")
            }
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: destination, isDirectory: &directory), directory.boolValue,
                  FileManager.default.isWritableFile(atPath: destination) else {
                throw AutomationFailure("destination_unavailable", "Destination is missing or not writable. No folder was created.")
            }
        }
    }
}

nonisolated struct AutomationFailure: Error, Codable, Sendable {
    let code: String
    let message: String
    init(_ code: String, _ message: String) { self.code = code; self.message = message }
}

nonisolated struct AutomationJob: Codable, Equatable, Sendable {
    let command: AutomationCommand
    var state: String
    var name: String?
    var fileCount: Int?
    var totalBytes: Int64?
    var isVideo: Bool?
    var outputPath: String?
    var errorCode: String?
    var message: String?
    var updatedAt: Date = .now
    var terminal: Bool { ["analyzed", "completed", "failed", "cancelled", "duplicate", "interrupted"].contains(state) }
}

nonisolated struct AutomationReply: Codable, Sendable {
    let id: UUID
    var ok: Bool = true
    var error: AutomationFailure?
    var job: AutomationJob?
    var appVersion: String?
    var queuePaused: Bool?
    var bytesDownloaded: Int64?
    var completedFiles: Int?
    var bytesPerSecond: Double?
    var percentage: Int?
}

import Foundation
import Darwin

/// Separate from the MCP spool. Contains sensitive resumable capabilities and
/// is accessed exclusively by the app; no adapter ever reads this directory.
@MainActor
final class UploadStore {
    let root: URL
    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DropDrive/Uploads/v1")) {
        self.root = root
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let values = try FileManager.default.attributesOfItem(atPath: root.path)
        guard values[.type] as? FileAttributeType == .typeDirectory,
              (values[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((values[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077 == 0 else {
            throw AutomationFailure("unsafe_permissions", "Upload storage must be a private directory owned by this macOS user.")
        }
    }

    func save(_ record: PrivateUploadRecord) throws {
        try prepare()
        let data = try JSONEncoder().encode(record)
        let target = root.appendingPathComponent(record.job.command.id.uuidString + ".json")
        try data.write(to: target, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        // Flush the generated ID/session checkpoint before an HTTP side effect.
        let fd = Darwin.open(target.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw AutomationFailure("checkpoint_failed", "Cannot flush upload checkpoint.") }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw AutomationFailure("checkpoint_failed", "Cannot durably save upload checkpoint. Check local disk space.") }
        let directory = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw AutomationFailure("checkpoint_failed", "Cannot flush upload checkpoint directory.") }
        defer { Darwin.close(directory) }
        guard fsync(directory) == 0 else { throw AutomationFailure("checkpoint_failed", "Cannot durably save upload checkpoint directory.") }
    }

    func delete(_ id: UUID) throws {
        let target = root.appendingPathComponent(id.uuidString + ".json")
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }

    func load() throws -> [UUID: PrivateUploadRecord] {
        try prepare()
        var result: [UUID: PrivateUploadRecord] = [:]
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            let fd = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { throw AutomationFailure("unsafe_checkpoint", "Cannot safely open an upload checkpoint.") }
            defer { Darwin.close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                  info.st_uid == getuid(), info.st_nlink == 1, info.st_mode & 0o077 == 0,
                  info.st_size <= 262_144 else {
                throw AutomationFailure("unsafe_checkpoint", "Upload checkpoint ownership or permissions are unsafe.")
            }
            let data = try FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd() ?? Data()
            let record = try JSONDecoder().decode(PrivateUploadRecord.self, from: data)
            guard file.lastPathComponent == record.job.command.id.uuidString + ".json" else {
                throw AutomationFailure("unsafe_checkpoint", "Upload checkpoint identity mismatch.")
            }
            result[record.job.command.id] = record
        }
        return result
    }
}

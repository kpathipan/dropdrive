import Foundation
import Darwin
import CryptoKit

/// Walk with openat/O_NOFOLLOW, then retain the descriptor for the whole transfer.
/// Reject symlinks in every component, devices, directories and FIFOs. There is
/// no Submit/Downloads allow-list and no application-defined file-size limit.
nonisolated final class UploadSource: @unchecked Sendable {
    let descriptor: Int32
    let identity: UploadSourceIdentity

    init(path: String) throws {
        guard path.hasPrefix("/"), !path.contains("\0") else {
            throw AutomationFailure("invalid_source", "Source must be an absolute local file path.")
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty, !parts.contains("."), !parts.contains("..") else {
            throw AutomationFailure("invalid_source", "Source must not contain relative path components.")
        }
        var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw AutomationFailure("source_unreadable", "Cannot open local source.") }
        for (index, part) in parts.enumerated() {
            let last = index == parts.count - 1
            let next = openat(fd, part, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | (last ? 0 : O_DIRECTORY))
            Darwin.close(fd)
            guard next >= 0 else {
                throw AutomationFailure("source_unreadable", "Cannot read this file safely. Select the real file, not a symbolic link, and check macOS permissions.")
            }
            fd = next
        }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else {
            Darwin.close(fd)
            throw AutomationFailure("invalid_source", "Upload a readable regular file. Folders, links and special files are not supported.")
        }
        descriptor = fd
        identity = Self.identity(info)
    }

    deinit { Darwin.close(descriptor) }

    private static func identity(_ info: stat) -> UploadSourceIdentity {
        UploadSourceIdentity(device: UInt64(UInt32(bitPattern: info.st_dev)), inode: UInt64(info.st_ino), size: info.st_size,
                             modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanos: Int64(info.st_mtimespec.tv_nsec))
    }

    func checkUnchanged() throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0, Self.identity(info) == identity else {
            throw AutomationFailure("source_changed", "The source file changed. Keep it unchanged for retry, or submit the edited file as a new upload.")
        }
    }

    func read(offset: Int64, count: Int) throws -> Data {
        try Task.checkCancellation()
        try checkUnchanged()
        guard offset >= 0, offset <= identity.size, count >= 0 else {
            throw AutomationFailure("invalid_offset", "Invalid upload offset.")
        }
        let length = min(Int64(count), identity.size - offset)
        var data = Data(count: Int(length))
        let readCount = data.withUnsafeMutableBytes { buffer in
            Darwin.pread(descriptor, buffer.baseAddress, Int(length), off_t(offset))
        }
        guard readCount == length else { throw AutomationFailure("source_unreadable", "Could not read the complete source chunk.") }
        return data
    }

    func md5() throws -> String {
        var digest = Insecure.MD5(), offset: Int64 = 0
        while offset < identity.size {
            let chunk = try read(offset: offset, count: 1_048_576)
            digest.update(data: chunk); offset += Int64(chunk.count)
        }
        try checkUnchanged()
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

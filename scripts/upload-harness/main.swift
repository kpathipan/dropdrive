import Foundation
import CryptoKit
import Darwin
import AppKit

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    guard condition() else { fatalError("FAIL \(name)") }
    FileHandle.standardOutput.write(Data("PASS \(name)\n".utf8))
}

nonisolated final class MockState: @unchecked Sendable {
    let lock = NSLock()
    var name = "source.bin", size: Int64 = 0, md5 = "", offset: Int64 = 0
    var generations = 0, sessions = 0, chunks: [Int64] = [], complete = false
    var loseACK = false, rejectHost = false, corruptMD5 = false, shared = false
    func reset(size: Int64, md5: String, loseACK: Bool = false, rejectHost: Bool = false, corrupt: Bool = false, shared: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        self.size = size; self.md5 = md5; self.loseACK = loseACK; self.rejectHost = rejectHost
        corruptMD5 = corrupt; self.shared = shared; offset = 0; generations = 0; sessions = 0; chunks = []; complete = false
    }
    func handle(_ request: URLRequest) -> (Int, [String: String], Data, Bool) {
        lock.lock(); defer { lock.unlock() }
        let url = request.url!, path = url.path, method = request.httpMethod ?? "GET"
        precondition(url.host == "www.googleapis.com", "Token must never be sent to another host")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-secret")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
        func response(_ code: Int, _ body: [String: Any] = [:], headers: [String: String] = [:], lost: Bool = false) -> (Int, [String: String], Data, Bool) {
            (code, headers, try! JSONSerialization.data(withJSONObject: body), lost)
        }
        if path.hasSuffix("/generateIds") { generations += 1; return response(200, ["ids": ["generated_id"]]) }
        if path == "/drive/v3/files/parent" {
            precondition(query["supportsAllDrives"] == "true")
            var folder: [String: Any] = ["id": "parent", "name": "Test destination", "mimeType": "application/vnd.google-apps.folder", "capabilities": ["canAddChildren": true]]
            if shared { folder["driveId"] = "shared_id" }
            return response(200, folder)
        }
        if path == "/drive/v3/files", method == "GET" {
            precondition(query["supportsAllDrives"] == "true" && query["includeItemsFromAllDrives"] == "true")
            if shared { precondition(query["corpora"] == "drive" && query["driveId"] == "shared_id") }
            return response(200, ["files": []])
        }
        if path == "/drive/v3/files/generated_id" {
            if !complete { return response(404) }
            return response(200, ["id": "generated_id", "name": name, "mimeType": "application/octet-stream", "size": String(size), "md5Checksum": corruptMD5 ? "bad" : md5, "parents": ["parent"], "trashed": false])
        }
        if path == "/upload/drive/v3/files", method == "POST" {
            precondition(query["supportsAllDrives"] == "true")
            // CFNetwork may move a data task's JSON body to a stream before
            // handing it to URLProtocol. The fixture accepts either form.
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }; data.append(contentsOf: buffer.prefix(count))
                }
                body = data
            }
            if let body, !body.isEmpty {
                let metadata = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
                precondition(metadata["id"] as? String == "generated_id")
                name = metadata["name"] as! String
            }
            sessions += 1
            return response(200, headers: ["Location": rejectHost ? "https://example.invalid/steal-session" : "https://www.googleapis.com/upload/drive/v3/files?upload_id=private-session"])
        }
        if method == "PUT" {
            let range = request.value(forHTTPHeaderField: "Content-Range")!
            if range.hasPrefix("bytes */") {
                if complete { return response(200) }
                return response(308, headers: offset == 0 ? [:] : ["Range": "bytes=0-\(offset-1)"])
            }
            let span = range.dropFirst(6).split(separator: "/")[0].split(separator: "-")
            let first = Int64(span[0])!, last = Int64(span[1])!
            precondition(first == offset && last >= first && last < size)
            chunks.append(first); offset = last + 1
            if offset == size { complete = true }
            if loseACK { loseACK = false; return response(503, lost: true) }
            return response(complete ? 200 : 308, headers: ["Range": "bytes=0-\(offset-1)"])
        }
        fatalError("Unexpected fixture request: \(method) \(path)")
    }
}

nonisolated final class MockProtocol: URLProtocol, @unchecked Sendable {
    static let backend = MockState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code, headers, data, lost) = Self.backend.handle(request)
        if lost { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

actor Checkpoints {
    var record: PrivateUploadRecord?
    var stopAfterChunk = false
    init(stopAfterChunk: Bool = false) { self.stopAfterChunk = stopAfterChunk }
    func save(_ value: PrivateUploadRecord) throws {
        // Every create request in these tests must have a durable ID first.
        record = value
        if stopAfterChunk, value.confirmedOffset >= 8 * 1048576 {
            stopAfterChunk = false; throw CancellationError()
        }
    }
}

@main struct UploadTests {
    static func main() async throws {
        // Foundation deliberately shortens /private/var back to /var on macOS.
        // Use realpath here so the security test itself has no symlink ancestor.
        let canonical = realpath(FileManager.default.temporaryDirectory.path, nil)!
        let temporaryPath = String(cString: canonical); free(canonical)
        let directory = URL(fileURLWithPath: temporaryPath).appendingPathComponent("dd-upload-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("source.bin")
        try Data(repeating: 0x49, count: 17 * 1048576).write(to: file)
        let source = try UploadSource(path: file.path), hash = try source.md5()
        check("source supports a regular file outside Submit", source.identity.size == 17 * 1048576)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([file as NSURL])
        check("native file drag pasteboard selects upload source", UploadDropFiles.files(from: pasteboard).map(\.path) == [file.path])
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        do { _ = try UploadSource(path: link.path); fatalError("symlink accepted") } catch { print("PASS final symlink rejected") }
        let directoryLink = directory.appendingPathComponent("dir-link")
        try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: directory)
        do { _ = try UploadSource(path: directoryLink.appendingPathComponent("source.bin").path); fatalError("parent symlink accepted") } catch { print("PASS parent symlink escape rejected") }
        do { _ = try UploadSource(path: directory.path); fatalError("directory accepted") } catch { print("PASS directories rejected") }
        let sparse = directory.appendingPathComponent("over100MB.bin")
        _ = FileManager.default.createFile(atPath: sparse.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sparse); try handle.truncate(atOffset: 128 * 1048576); try handle.close()
        let largeSource = try UploadSource(path: sparse.path)
        check("no invented 100 MB source cap", largeSource.identity.size == 128 * 1048576)

        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let engine = DriveUploadEngine(session: URLSession(configuration: config), tokens: { account, _ in GoogleAccessToken(accountID: account, token: "fixture-secret") })
        func record() -> PrivateUploadRecord {
            let command = AutomationCommand(id: UUID(), action: "upload", name: "source.bin", sourcePath: file.path, driveFolder: "parent", accountID: "test-account")
            return PrivateUploadRecord(job: AutomationJob(command: command, state: "queued", upload: UploadStatus()), effectiveName: "source.bin", accountID: "test-account")
        }
        MockProtocol.backend.reset(size: source.identity.size, md5: hash, loseACK: true, shared: true)
        let checkpoints = Checkpoints()
        let completed = try await engine.run(record(), checkpoint: { try await checkpoints.save($0) }, progress: { _ in })
        check("lost ACK resumes at server offset without creating another file", MockProtocol.backend.generations == 1 && MockProtocol.backend.sessions == 1 && MockProtocol.backend.chunks == [0, 8 * 1048576, 16 * 1048576])
        check("Shared Drive upload is verified by exact parent/size/MD5", completed.job.upload?.verified == true && completed.job.upload?.folder?.driveID == "shared_id")
        let publicJSON = String(data: try JSONEncoder().encode(AutomationReply(id: UUID(), job: completed.job)), encoding: .utf8)!
        check("public IPC excludes tokens and resumable capabilities", !publicJSON.contains("fixture-secret") && !publicJSON.contains("private-session") && !publicJSON.contains("upload_id"))

        MockProtocol.backend.reset(size: source.identity.size, md5: hash)
        let interrupted = Checkpoints(stopAfterChunk: true)
        do { _ = try await engine.run(record(), checkpoint: { try await interrupted.save($0) }, progress: { _ in }); fatalError("expected cancellation") }
        catch is CancellationError { print("PASS cancellation exits after a durable acknowledged chunk") }
        let saved = await interrupted.record!
        let restored = try JSONDecoder().decode(PrivateUploadRecord.self, from: JSONEncoder().encode(saved))
        let resumed = try await engine.run(restored, checkpoint: { try await interrupted.save($0) }, progress: { _ in })
        check("serialized checkpoint resumes the same ID/session after interruption", resumed.job.upload?.verified == true && MockProtocol.backend.generations == 1 && MockProtocol.backend.sessions == 1)

        MockProtocol.backend.reset(size: source.identity.size, md5: hash, rejectHost: true)
        do { _ = try await engine.run(record(), checkpoint: { try await checkpoints.save($0) }, progress: { _ in }); fatalError("unsafe endpoint accepted") }
        catch let error as AutomationFailure { check("untrusted resumable host rejected before token transmission", error.code == "invalid_session") }
        MockProtocol.backend.reset(size: source.identity.size, md5: hash, corrupt: true)
        do { _ = try await engine.run(record(), checkpoint: { try await checkpoints.save($0) }, progress: { _ in }); fatalError("bad checksum accepted") }
        catch let error as AutomationFailure { check("remote checksum mismatch cannot claim completion", error.code == "integrity_mismatch") }
        var changed = restored
        try Data([0x11]).write(to: file)
        do { _ = try await engine.run(changed, checkpoint: { try await checkpoints.save($0) }, progress: { _ in }); fatalError("changed source accepted") }
        catch let error as AutomationFailure { check("changed source rejected before a resumed PUT", error.code == "source_changed") }
        changed.sessionURL = "private-session"
        let store = UploadStore(root: directory.appendingPathComponent("private-store"))
        try store.save(changed)
        let stored = try store.load()
        check("private checkpoint survives restart with original ID", stored[changed.job.command.id]?.fileID == "generated_id")
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("private-store/\(changed.job.command.id.uuidString).json").path)
        check("private checkpoint mode is 0600", (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        print("ALL UPLOAD ENGINE CHECKS PASS")
    }
}

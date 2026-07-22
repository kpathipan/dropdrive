import Foundation

// A synthetic Drive served through URLProtocol: a folder tree for the scan
// tests, and real file bytes (range requests included) for the download tests.

let latency: UInt64 = 120_000_000 // 120ms per API round trip

struct Node { let id: String; let children: [String]; let files: Int }

var tree: [String: Node] = [:]
var rootKids: [String] = []
for a in 0..<4 {
    let idA = "a\(a)"
    rootKids.append(idA)
    var kidsA: [String] = []
    for b in 0..<3 {
        let idB = "b\(a)_\(b)"
        kidsA.append(idB)
        tree[idB] = Node(id: idB, children: [], files: 5)
    }
    tree[idA] = Node(id: idA, children: kidsA, files: 2)
}
tree["root"] = Node(id: "root", children: rootKids, files: 1)
// A shortcut cycle: the last leaf claims the root as a child.
tree["b3_2"] = Node(id: "b3_2", children: ["root"], files: 5)

let expectedFiles = 1 + 4 * 2 + 12 * 5
let fileSize = 1000
let expectedBytes = Int64(expectedFiles * fileSize)

// Deterministic content for a file ID, so a download can be checked byte for byte.
func contents(for id: String, size: Int) -> Data {
    var data = Data(capacity: size)
    let seed = Array(id.utf8)
    for i in 0..<size { data.append(seed[i % seed.count] &+ UInt8(i % 251)) }
    return data
}

// The one big file used for the multi-part range test.
let bigID = "bigfile"
let bigSize = 300 * 1024 * 1024 / 1000 // 300 KB stand-in; size is faked in metadata
let bigDeclaredSize = 300 * 1024 * 1024

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var live = 0
    private var peak = 0
    func hit(_ kind: String) { lock.lock(); counts[kind, default: 0] += 1; lock.unlock() }
    func enter() { lock.lock(); live += 1; peak = max(peak, live); lock.unlock() }
    func leave() { lock.lock(); live -= 1; lock.unlock() }
    func count(_ kind: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[kind] ?? 0 }
    var maxConcurrent: Int { lock.lock(); defer { lock.unlock() }; return peak }
    func reset() { lock.lock(); counts = [:]; live = 0; peak = 0; lock.unlock() }
}
let counter = Counter()

final class DriveStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "www.googleapis.com"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        let url = request.url!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let query = components.queryItems ?? []
        let isMedia = query.contains { $0.name == "alt" && $0.value == "media" }
        let rangeHeader = request.value(forHTTPHeaderField: "Range")

        if isMedia {
            counter.hit("media")
            if rangeHeader != nil { counter.hit("range") }
            let id = url.lastPathComponent
            let size = id == bigID ? bigDeclaredSize : fileSize
            let body = contents(for: id, size: size)

            if let rangeHeader, let spec = rangeHeader.split(separator: "=").last {
                let parts = spec.split(separator: "-", omittingEmptySubsequences: false)
                let lower = Int(parts[0]) ?? 0
                let upper = parts.count > 1 ? (Int(parts[1]) ?? size - 1) : size - 1
                let slice = body[lower...min(upper, size - 1)]
                let response = HTTPURLResponse(
                    url: url, statusCode: 206, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Range": "bytes \(lower)-\(upper)/\(size)",
                                   "Content-Length": "\(slice.count)"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(slice))
                client?.urlProtocolDidFinishLoading(self)
                return
            }

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Length": "\(body.count)"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        counter.enter()
        Task {
            try? await Task.sleep(nanoseconds: latency)
            counter.leave()

            let body: [String: Any]
            if let q = query.first(where: { $0.name == "q" })?.value,
               let start = q.range(of: "'"), let end = q.range(of: "' in parents") {
                counter.hit("list")
                let folderID = String(q[start.upperBound..<end.lowerBound])
                let node = tree[folderID]!
                var files: [[String: Any]] = []
                for c in node.children {
                    files.append(["id": c, "name": c, "mimeType": "application/vnd.google-apps.folder"])
                }
                for f in 0..<node.files {
                    files.append(["id": "\(folderID)_f\(f)", "name": "\(folderID)_f\(f).jpg",
                                  "mimeType": "image/jpeg", "size": "\(fileSize)"])
                }
                body = ["files": files]
            } else {
                counter.hit("metadata")
                let id = url.lastPathComponent
                if id == bigID {
                    body = ["id": id, "name": "big.bin", "mimeType": "application/octet-stream",
                            "size": "\(bigDeclaredSize)"]
                } else if tree[id] != nil {
                    body = ["id": id, "name": id, "mimeType": "application/vnd.google-apps.folder"]
                } else {
                    body = ["id": id, "name": "\(id).jpg", "mimeType": "image/jpeg", "size": "\(fileSize)"]
                }
            }

            let data = try! JSONSerialization.data(withJSONObject: body)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

EphemeralConfigPatch.protocolClass = DriveStub.self
EphemeralConfigPatch.install()
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [DriveStub.self]
let session = URLSession(configuration: config)
let service = GoogleDriveDownloadService(loginManager: StubLogin(), urlSession: session)

var failures = 0
func check(_ label: String, _ actual: Any, _ expected: Any) {
    let ok = "\(actual)" == "\(expected)"
    print("\(ok ? "PASS" : "FAIL") \(label): got \(actual), expected \(expected)")
    if !ok { failures += 1 }
}
func pass(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("\(condition ? "PASS" : "FAIL") \(label)\(detail.isEmpty ? "" : ": \(detail)")")
    if !condition { failures += 1 }
}

// MARK: - 1. Folder analysis

print("--- folder analysis")
let started = Date()
let result = try await service.analyzeLink(itemID: "root", resourceKey: nil)
let elapsed = Date().timeIntervalSince(started)

guard case .success(let analysis) = result else {
    print("FAIL: analysis did not succeed: \(result)")
    exit(1)
}
check("fileCount", analysis.fileCount ?? -1, expectedFiles)
check("totalBytes", analysis.totalBytes ?? -1, expectedBytes)
check("images in breakdown", analysis.categoryBreakdown?.images ?? -1, expectedFiles)
check("folder listings", counter.count("list"), 17)
let sequentialFloor = 18 * 0.12
pass("parallel scan", elapsed < sequentialFloor * 0.6,
     String(format: "%.2fs vs %.2fs sequential", elapsed, sequentialFloor))
pass("concurrency cap respected", counter.maxConcurrent <= 6, "peak \(counter.maxConcurrent)")
pass("terminated despite a folder cycle", true)

// MARK: - 2. Folder download

print("--- folder download")
let sandbox = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dd-harness-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: sandbox) }

counter.reset()
let folderRequest = DownloadRequest(driveLink: "x", itemID: "root", destinationURL: sandbox,
                                    resourceKey: nil, resumeID: UUID())
let folderURL = try await service.download(folderRequest) { _ in }

var downloaded = 0
var corrupt: [String] = []
if let walker = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
    for case let url as URL in walker {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
        downloaded += 1
        let id = url.deletingPathExtension().lastPathComponent
        let onDisk = try Data(contentsOf: url)
        if onDisk != contents(for: id, size: fileSize) { corrupt.append(url.lastPathComponent) }
    }
}
check("files written", downloaded, expectedFiles)
pass("every file byte-identical", corrupt.isEmpty, corrupt.isEmpty ? "" : "\(corrupt.count) wrong: \(corrupt.prefix(3))")
var leftovers = 0
if let sweep = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: nil) {
    for case let url as URL in sweep where url.pathExtension == "dddownload" { leftovers += 1 }
}
check("no .dddownload left behind", leftovers, 0)

// MARK: - 3. Resume: an interrupted folder only re-fetches what's missing
//
// A *completed* folder has its in-progress marker cleared, so downloading the
// same link again is deliberately a fresh copy ("root (1)"). To exercise the
// resume path, put the marker back and delete a few files, the state a killed
// run leaves behind.

print("--- folder resume")
try "root".write(to: folderURL.appendingPathComponent(".dropdrive-inprogress"),
                 atomically: true, encoding: .utf8)
var deleted: [URL] = []
if let walker = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
    var found: [URL] = []
    for case let url as URL in walker where url.pathExtension == "jpg" { found.append(url) }
    deleted = Array(found.prefix(3))
}
for url in deleted { try FileManager.default.removeItem(at: url) }

let mediaBefore = counter.count("media")
let secondRoot = try await service.download(
    DownloadRequest(driveLink: "x", itemID: "root", destinationURL: sandbox,
                    resourceKey: nil, resumeID: UUID())) { _ in }
check("resumed into the same folder", secondRoot.path, folderURL.path)
check("only the missing files re-downloaded", counter.count("media") - mediaBefore, deleted.count)
pass("deleted files restored", deleted.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

// MARK: - 4. Multi-part ranged download of a large file

print("--- multi-part download")
counter.reset()
let bigDest = sandbox.appendingPathComponent("big")
try FileManager.default.createDirectory(at: bigDest, withIntermediateDirectories: true)
let bigURL = try await service.download(
    DownloadRequest(driveLink: "x", itemID: bigID, destinationURL: bigDest,
                    resourceKey: nil, resumeID: UUID())) { _ in }
let bigOnDisk = try Data(contentsOf: bigURL)
check("large file size", bigOnDisk.count, bigDeclaredSize)
pass("large file byte-identical", bigOnDisk == contents(for: bigID, size: bigDeclaredSize))
// 300 MB -> 6 ranges, plus the one-time range-support probe.
pass("split into 6 ranges", counter.count("range") == 7, "\(counter.count("range")) ranged requests (6 + 1 probe)")

// MARK: - 5. The range probe is cached per host

print("--- range probe caching")
let rangeBefore = counter.count("range")
_ = try await service.download(
    DownloadRequest(driveLink: "x", itemID: bigID, destinationURL: bigDest,
                    resourceKey: nil, resumeID: UUID())) { _ in }
check("second large file: ranges without a fresh probe", counter.count("range") - rangeBefore, 6)

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)

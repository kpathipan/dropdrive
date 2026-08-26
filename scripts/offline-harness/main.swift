import Foundation
import CryptoKit

nonisolated func descendants(of folder: URL, skipsHidden: Bool = false) -> [URL] {
    let options: FileManager.DirectoryEnumerationOptions = skipsHidden ? [.skipsHiddenFiles] : []
    guard let walker = FileManager.default.enumerator(
        at: folder,
        includingPropertiesForKeys: nil,
        options: options
    ) else { return [] }
    return walker.compactMap { $0 as? URL }
}

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

// Three files sharing one name inside the root folder. Declared before it is
// used: top level runs in order, and reading it above its own line is a
// use-before-initialisation that segfaults rather than failing to compile.
let duplicateNameIDs = ["dup_c", "dup_a", "dup_b"]
let expectedFiles = 1 + 4 * 2 + 12 * 5 + duplicateNameIDs.count
let fileSize = 1000
let expectedBytes = Int64(expectedFiles * fileSize)

// Deterministic content for a file ID, so a download can be checked byte for byte.
func contents(for id: String, size: Int) -> Data {
    var data = Data(capacity: size)
    let seed = Array(id.utf8)
    for i in 0..<size { data.append(seed[i % seed.count] &+ UInt8(i % 251)) }
    return data
}

func md5(for id: String, size: Int) -> String {
    Insecure.MD5.hash(data: contents(for: id, size: size))
        .map { String(format: "%02x", $0) }
        .joined()
}

// The one big file used for the multi-part range test.
let bigID = "bigfile"
// A file whose Drive name carries no extension.
let bareID = "barename"
// A file whose Drive name ends in something that only looks like one.
let timestampID = "timestamped"
// Metadata deliberately disagrees with the served bytes for integrity cleanup.
let corruptID = "corrupt-checksum"
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
                    let id = "\(folderID)_f\(f)"
                    files.append(["id": id, "name": "\(id).jpg",
                                  "mimeType": "image/jpeg", "size": "\(fileSize)",
                                  "md5Checksum": md5(for: id, size: fileSize)])
                }
                // Drive identifies files by id, so one folder really can hold
                // several files with identical names. Only the root carries
                // them, to keep the counts elsewhere unchanged.
                if folderID == "root" {
                    for (index, id) in duplicateNameIDs.enumerated() {
                        files.append(["id": id, "name": "invoice.pdf",
                                      "mimeType": "application/pdf", "size": "\(fileSize)",
                                      "md5Checksum": md5(for: id, size: fileSize)])
                        _ = index
                    }
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
                } else if id == bareID {
                    // A real case from Drive: a clip uploaded under a name with no
                    // extension at all, its type known only from the metadata.
                    body = ["id": id, "name": "Vo", "mimeType": "video/mp4", "size": "\(fileSize)",
                            "md5Checksum": md5(for: id, size: fileSize)]
                } else if id == timestampID {
                    // The other real shape: a name whose trailing ".549Z" is part
                    // of a timestamp, which macOS reads as an unknown extension.
                    body = ["id": id, "name": "ไฟล์ - 2026-08-10T05:03:42.549Z",
                            "mimeType": "video/quicktime", "size": "\(fileSize)",
                            "md5Checksum": md5(for: id, size: fileSize)]
                } else if id == corruptID {
                    body = ["id": id, "name": "corrupt.bin", "mimeType": "application/octet-stream",
                            "size": "\(fileSize)", "md5Checksum": String(repeating: "0", count: 32)]
                } else {
                    body = ["id": id, "name": "\(id).jpg", "mimeType": "image/jpeg", "size": "\(fileSize)",
                            "md5Checksum": md5(for: id, size: fileSize)]
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
check("images in breakdown", analysis.categoryBreakdown?.images ?? -1, expectedFiles - duplicateNameIDs.count)
check("documents in breakdown", analysis.categoryBreakdown?.documents ?? -1, duplicateNameIDs.count)
check("folder manifest", analysis.folderItems?.count ?? -1, expectedFiles)
let imageOnly = analysis.selectingFolderItems(Set(["root_f0", "a0_f0"]))
check("selected analysis fileCount", imageOnly.fileCount ?? -1, 2)
check("selected analysis bytes", imageOnly.totalBytes ?? -1, Int64(fileSize * 2))
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

// While the download runs, sample how long the main actor stays blocked. The
// engine creates directories, stats every planned file and sweeps stale staging
// files; when that ran main-actor-isolated the sampler below starved.
final class Stall: @unchecked Sendable {
    private let lock = NSLock()
    private var worst: Double = 0
    func record(_ gap: Double) { lock.lock(); worst = max(worst, gap); lock.unlock() }
    var worstGap: Double { lock.lock(); defer { lock.unlock() }; return worst }
}
let stall = Stall()
let sampling = Task { @MainActor in
    var last = Date()
    while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 2_000_000)
        let now = Date()
        stall.record(now.timeIntervalSince(last))
        last = now
    }
}

let folderURL = try await service.download(folderRequest) { _ in }
sampling.cancel()
pass("main actor stayed responsive during the download",
     stall.worstGap < 0.25, String(format: "worst stall %.0f ms", stall.worstGap * 1000))

var downloaded = 0
var corrupt: [String] = []
for url in descendants(of: folderURL, skipsHidden: true) {
    guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
    downloaded += 1
    // The same-name files are checked on their own below: their id can't be
    // recovered from a filename they had to be renamed out of.
    guard !url.lastPathComponent.hasPrefix("invoice") else { continue }
    let id = url.deletingPathExtension().lastPathComponent
    let onDisk = try Data(contentsOf: url)
    if onDisk != contents(for: id, size: fileSize) { corrupt.append(url.lastPathComponent) }
}
check("files written", downloaded, expectedFiles)
pass("every file byte-identical", corrupt.isEmpty, corrupt.isEmpty ? "" : "\(corrupt.count) wrong: \(corrupt.prefix(3))")
let leftovers = descendants(of: folderURL).filter { $0.pathExtension == "dddownload" }.count
check("no .dddownload left behind", leftovers, 0)

// Drive lets one folder hold several files with the same name; downloaded
// as-is they all take the same path and silently overwrite each other.
let sameName = ((try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil))  ?? [])
    .filter { $0.lastPathComponent.hasPrefix("invoice") }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
check("every same-named file kept", sameName.count, duplicateNameIDs.count)
// The lowest file id keeps the unsuffixed name — that is what makes the
// assignment reproducible on a resume, and it is not the order Drive listed
// them in (the stub lists dup_c first).
let plainName = sameName.first { $0.lastPathComponent == "invoice.pdf" }
pass("the plain name went to the lowest file id",
     plainName.flatMap { try? Data(contentsOf: $0) } == contents(for: duplicateNameIDs.sorted()[0], size: fileSize),
     "expected \(duplicateNameIDs.sorted()[0])'s bytes in invoice.pdf")
let sameNameBytes = Set(sameName.compactMap { try? Data(contentsOf: $0) })
check("each holds its own file's bytes, none overwritten", sameNameBytes.count, duplicateNameIDs.count)
// Suffixes are assigned in file-id order so a resume finds the same names.
check("suffixes assigned deterministically by id",
      sameName.map(\.lastPathComponent).joined(separator: ","),
      "invoice (2).pdf,invoice (3).pdf,invoice.pdf")

// MARK: - 2b. Selective folder download

print("--- selective folder download")
let selectiveDestination = sandbox.appendingPathComponent("selective")
try FileManager.default.createDirectory(at: selectiveDestination, withIntermediateDirectories: true)
let selectiveIDs: Set<String> = ["root_f0", "a0_f0"]
let selectiveMediaBefore = counter.count("media")
let selectiveListingsBefore = counter.count("list")
let selectedManifest = analysis.folderItems?.filter { selectiveIDs.contains($0.id) } ?? []
pass("selected manifest keeps Drive checksums", selectedManifest.allSatisfy { $0.md5Checksum != nil })
let selectiveURL = try await service.download(
    DownloadRequest(
        driveLink: "x",
        itemID: "root",
        destinationURL: selectiveDestination,
        resourceKey: nil,
        resumeID: UUID(),
        selectedFileIDs: selectiveIDs,
        selectedFolderItems: selectedManifest
    )
) { _ in }
let selectiveFiles = descendants(of: selectiveURL, skipsHidden: true).filter {
    (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
}
check("only selected files fetched", counter.count("media") - selectiveMediaBefore, selectiveIDs.count)
check("selected files skip a second folder scan", counter.count("list") - selectiveListingsBefore, 0)
check("only selected files written", selectiveFiles.count, selectiveIDs.count)
let emptyDirectories = descendants(of: selectiveURL, skipsHidden: true).filter { url in
    guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
    return (try? FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty) == true
}
check("no empty unselected folders left", emptyDirectories.count, 0)

// MARK: - 3. Resume: an interrupted folder only re-fetches what's missing
//
// A *completed* folder has its in-progress marker cleared, so downloading the
// same link again is deliberately a fresh copy ("root (1)"). To exercise the
// resume path, put the marker back and delete a few files, the state a killed
// run leaves behind.

print("--- folder resume")
try "root".write(to: folderURL.appendingPathComponent(".dropdrive-inprogress"),
                 atomically: true, encoding: .utf8)
let deleted = Array(descendants(of: folderURL, skipsHidden: true).filter { $0.pathExtension == "jpg" }.prefix(3))
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

// MARK: - 6. A single file never overwrites something already there

print("--- single-file overwrite protection")
let singleDest = sandbox.appendingPathComponent("single")
try FileManager.default.createDirectory(at: singleDest, withIntermediateDirectories: true)
// A file of the user's that happens to share the name Drive will hand back.
let collision = singleDest.appendingPathComponent("solo.jpg")
let precious = Data("do not lose me".utf8)
try precious.write(to: collision)

let soloURL = try await service.download(
    DownloadRequest(driveLink: "x", itemID: "solo", destinationURL: singleDest,
                    resourceKey: nil, resumeID: UUID())) { _ in }
check("downloaded alongside, not over", soloURL.lastPathComponent, "solo (1).jpg")
check("the existing file is untouched", try Data(contentsOf: collision), precious)
pass("the new file has the downloaded bytes",
     (try Data(contentsOf: soloURL)) == contents(for: "solo", size: fileSize))

// Google supplies md5Checksum for uploaded binary files. A mismatch must never
// leave a file that Finder or a resume pass could mistake for completed.
do {
    _ = try await service.download(
        DownloadRequest(driveLink: "x", itemID: corruptID, destinationURL: singleDest,
                        resourceKey: nil, resumeID: UUID())) { _ in }
    pass("checksum mismatch is rejected", false)
} catch DriveDownloadError.integrityMismatch {
    pass("checksum mismatch is rejected", true)
}
pass("checksum mismatch removes the bad file",
     !FileManager.default.fileExists(atPath: singleDest.appendingPathComponent("corrupt.bin").path))

// MARK: - 7. Renaming before the download starts

print("--- rename before download")
let renameDest = sandbox.appendingPathComponent("renamed")
try FileManager.default.createDirectory(at: renameDest, withIntermediateDirectories: true)

let renamedFile = try await service.download(
    DownloadRequest(driveLink: "x", itemID: "solo", destinationURL: renameDest,
                    resourceKey: nil, resumeID: UUID(), customName: "holiday clip")) { _ in }
check("file saved under the typed name", renamedFile.lastPathComponent, "holiday clip.jpg")
pass("renamed file has the downloaded bytes",
     (try Data(contentsOf: renamedFile)) == contents(for: "solo", size: fileSize))

// Typing the extension in as well must not double it up.
let withExtension = try await service.download(
    DownloadRequest(driveLink: "x", itemID: "solo", destinationURL: renameDest,
                    resourceKey: nil, resumeID: UUID(), customName: "beach.JPG")) { _ in }
check("a typed extension isn't doubled", withExtension.lastPathComponent, "beach.JPG")

// A "/" would otherwise silently turn the name into a subfolder path.
let slashed = try await service.download(
    DownloadRequest(driveLink: "x", itemID: "solo", destinationURL: renameDest,
                    resourceKey: nil, resumeID: UUID(), customName: "a/b")) { _ in }
check("a slash can't escape the destination folder", slashed.lastPathComponent, "a-b.jpg")
check("and nothing was written outside it", slashed.deletingLastPathComponent().path, renameDest.path)

let renamedFolder = try await service.download(
    DownloadRequest(driveLink: "x", itemID: "root", destinationURL: renameDest,
                    resourceKey: nil, resumeID: UUID(), customName: "My Folder")) { _ in }
check("folder created under the typed name", renamedFolder.lastPathComponent, "My Folder")
let renamedCount = descendants(of: renamedFolder, skipsHidden: true).filter {
    (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
}.count
check("renaming a folder doesn't rename what's inside it", renamedCount, expectedFiles)

// MARK: - 8. A file Drive names without an extension

print("--- extension from the file's declared type")
let bareDest = sandbox.appendingPathComponent("bare")
try FileManager.default.createDirectory(at: bareDest, withIntermediateDirectories: true)

let bareURL = try await service.download(
    DownloadRequest(driveLink: "x", itemID: bareID, destinationURL: bareDest,
                    resourceKey: nil, resumeID: UUID())) { _ in }
check("extension taken from the mime type", bareURL.lastPathComponent, "Vo.mp4")
pass("bytes are the file's own", (try Data(contentsOf: bareURL)) == contents(for: bareID, size: fileSize))

// Renaming one of these still can't strip the type back off.
let bareRenamed = try await service.download(
    DownloadRequest(driveLink: "x", itemID: bareID, destinationURL: bareDest,
                    resourceKey: nil, resumeID: UUID(), customName: "intro shot")) { _ in }
check("a renamed one keeps the type too", bareRenamed.lastPathComponent, "intro shot.mp4")

// ".549Z" is a timestamp fragment, not a type — macOS shows the same blank
// "?" document for it as for no extension at all.
let stampedURL = try await service.download(
    DownloadRequest(driveLink: "x", itemID: timestampID, destinationURL: bareDest,
                    resourceKey: nil, resumeID: UUID())) { _ in }
check("an extension that types nothing gets a real one appended",
      stampedURL.lastPathComponent, "ไฟล์ - 2026-08-10T05-03-42.549Z.mov")

// A real extension is left alone even where the declared type disagrees:
// "big.bin" is served as application/octet-stream and must stay as it is.
let untouched = try await service.download(
    DownloadRequest(driveLink: "x", itemID: bigID, destinationURL: bareDest,
                    resourceKey: nil, resumeID: UUID())) { _ in }
check("a name with a real extension is left alone", untouched.lastPathComponent, "big.bin")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)

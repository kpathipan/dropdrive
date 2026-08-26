import Foundation

var failures = 0
func check(_ label: String, _ condition: @autoclosure () -> Bool) {
    let passed = condition()
    print("\(passed ? "PASS" : "FAIL") \(label)")
    if !passed { failures += 1 }
}

check("missing capacity is unknown", DestinationCapacity.normalized(important: nil, ordinary: nil) == .unknown)
check("NAS zero capacity is unknown", DestinationCapacity.normalized(important: 0, ordinary: 0) == .unknown)
check("ordinary capacity is a valid fallback", DestinationCapacity.normalized(important: 0, ordinary: 16_000_000) == .available(16_000_000))
check("best positive capacity wins", DestinationCapacity.normalized(important: 32_000_000, ordinary: 16_000_000) == .available(32_000_000))

check("successful phone handoff is consumed", ExternalLinkReceipt(queued: 1).disposition == .consume)
check("known duplicate phone handoff is consumed", ExternalLinkReceipt(duplicates: 1).disposition == .consume)
check("transient phone failure is retained", ExternalLinkReceipt(retryableFailures: 1).disposition == .retry)
check("unsupported phone handoff is archived", ExternalLinkReceipt(unsupported: 1).disposition == .archiveRejected)
check("retry wins for mixed handoff", ExternalLinkReceipt(queued: 1, retryableFailures: 1, unsupported: 1).disposition == .retry)

let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
defer { try? FileManager.default.removeItem(at: scratch) }
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
let original = scratch.appendingPathComponent("link.txt")
FileManager.default.createFile(atPath: original.path, contents: Data())
check("rejected inputs keep a unique original", UniqueDestinationNaming.uniqueURL(for: original).lastPathComponent == "link (1).txt")

let bookmarkTestKey = "DropDrive.regression.disconnectedBookmark.\(UUID().uuidString)"
let rememberedPath = "/Volumes/Disconnected NAS/Downloads"
UserDefaults.standard.set(Data([0, 1, 2, 3]), forKey: bookmarkTestKey)
UserDefaults.standard.set(rememberedPath, forKey: "\(bookmarkTestKey).path")
check(
    "disconnected bookmark keeps its remembered path",
    SecurityScopedBookmark.restore(forKey: bookmarkTestKey)?.path == rememberedPath
)
SecurityScopedBookmark.clear(forKey: bookmarkTestKey)
check(
    "bookmark clear also removes its path fallback",
    UserDefaults.standard.object(forKey: "\(bookmarkTestKey).path") == nil
)

if failures > 0 { exit(1) }
print("ALL PASS")

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
check("retry receipt retains its exact link", ExternalLinkReceipt(retryableFailures: 1, retryableLinks: ["https://drive.google.com/file/d/retry/view"]).retryableLinks.count == 1)

let mixedLinks = SupportedLinkExtractor.links(from: """
Notes https://example.com/nope
https://drive.google.com/file/d/drive-item/view
https://youtu.be/abc123?si=first
https://www.youtube.com/watch?v=abc123&utm_source=duplicate
https://drive.google.com/file/d/drive-item/view?resourcekey=better-key
""")
check("supported-link extraction ignores unrelated URLs", mixedLinks.count == 2)
check("supported-link extraction preserves source order", mixedLinks.first?.contains("drive-item") == true)
check("supported-link extraction deduplicates video variants", mixedLinks.last?.contains("youtu") == true)
check("Drive duplicate keeps its resource key", GoogleDriveLinkParser.resourceKey(from: mixedLinks[0]) == "better-key")

let sharedLinks = ShareLinkExtractor.links(from: """
Look at https://example.com/ignored
https://drive.google.com/file/d/shared-drive/view?resourcekey=key&usp=sharing
https://youtu.be/shared-video
https://youtu.be/shared-video
""")
check("Share menu extracts several supported links", sharedLinks.count == 2)
check("Share menu removes exact duplicates", sharedLinks.last == "https://youtu.be/shared-video")
if let handoff = ShareLinkExtractor.deepLink(for: sharedLinks),
   let handoffComponents = URLComponents(url: handoff, resolvingAgainstBaseURL: false) {
    let handedOffLinks = (handoffComponents.queryItems ?? [])
        .filter { $0.name == "url" }
        .compactMap { $0.value }
    check("Share menu sends repeated URL query items", handedOffLinks == sharedLinks)
    check("Share menu preserves Drive resource keys", handedOffLinks.first?.contains("resourcekey=key&usp=sharing") == true)
} else {
    check("Share menu creates a valid handoff URL", false)
}

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

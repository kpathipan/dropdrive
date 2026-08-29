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

let selectableItems = [
    DriveLinkAnalysis.FolderItem(
        id: "one", name: "one.mp4", relativePath: "one.mp4", mimeType: "video/mp4",
        size: 100, category: .videos, md5Checksum: "a"
    ),
    DriveLinkAnalysis.FolderItem(
        id: "two", name: "two.pdf", relativePath: "two.pdf", mimeType: "application/pdf",
        size: 200, category: .documents, md5Checksum: "b"
    )
]
let folderAnalysis = DriveLinkAnalysis(
    itemID: "folder", name: "Folder", type: .folder, isPublic: true,
    requiresAuthentication: false, totalBytes: 300, fileCount: 2, ownerName: nil,
    categoryBreakdown: nil, folderItems: selectableItems
)
check("untouched folder selection keeps every file", folderAnalysis.selectingFolderItems(nil).fileCount == 2)
check("empty folder selection means zero files", folderAnalysis.selectingFolderItems([]).fileCount == 0)
check("individual folder selection uses selected bytes", folderAnalysis.selectingFolderItems(["two"]).totalBytes == 200)

let mediaDetails = DriveLinkAnalysis.VideoDetails(
    platform: "Youtube", availableHeights: [1080, 720],
    estimatedBytesByQuality: ["p720": 10_000], subtitleLanguages: ["en"],
    chapters: [.init(id: "c1", title: "Intro", startTime: 0, endTime: 10)],
    mediaItems: [
        .init(id: "m1", index: 1, title: "One", thumbnailURL: nil, durationSeconds: 10, isImage: false),
        .init(id: "m2", index: 2, title: "Two", thumbnailURL: nil, durationSeconds: 12, isImage: false)
    ]
)
let mediaAnalysis = DriveLinkAnalysis(
    itemID: "playlist", name: "Playlist", type: .file, isPublic: true,
    requiresAuthentication: false, totalBytes: nil, fileCount: nil, ownerName: nil,
    categoryBreakdown: nil, isVideo: true, videoDetails: mediaDetails
)
let queueItem = QueueItem(
    driveLink: "https://youtube.com/playlist?list=test", analysis: mediaAnalysis,
    videoQuality: .p720, subtitleMode: .embedded, splitChapters: true,
    saveThumbnail: true, selectedMediaIndexes: [2]
)
let queueRoundTrip = try JSONDecoder().decode(QueueItem.self, from: JSONEncoder().encode(queueItem))
check("video quality survives queue persistence", queueRoundTrip.videoQuality == .p720)
check("subtitle mode survives queue persistence", queueRoundTrip.subtitleMode == .embedded)
check(
    "TikTok photo URLs deduplicate by post ID",
    LinkIdentity.videoItemID(for: "https://www.tiktok.com/@creator/photo/7527319704663362829?share_id=one")
        == LinkIdentity.videoItemID(for: "https://m.tiktok.com/@creator/photo/7527319704663362829")
)
check("playlist selection survives queue persistence", queueRoundTrip.selectedMediaIndexes == [2])
check("playlist metadata remains a collection", queueRoundTrip.analysis.videoDetails?.isCollection == true)

if failures > 0 { exit(1) }
print("ALL PASS")

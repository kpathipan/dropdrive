import AVFoundation
import Foundation

func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else { fatalError("FAIL: " + label) }
    print("PASS: " + label)
}

let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent("dropdrive-media-test-" + UUID().uuidString)
try manager.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: root) }

// Sweep ownership: old system/unknown files and symlinks must survive.
let oldDate = Date().addingTimeInterval(-48 * 3600)
let cache = root.appendingPathComponent("DropDrive-info")
try manager.createDirectory(at: cache, withIntermediateDirectories: true)
let oldCache = cache.appendingPathComponent("old.json")
let recentCache = cache.appendingPathComponent("recent.json")
let foreign = root.appendingPathComponent("CFNetworkDownload_other.tmp")
let unknown = root.appendingPathComponent("DropDrive-unclaimed.tmp")
for url in [oldCache, recentCache, foreign, unknown] { try Data("fixture".utf8).write(to: url) }
for url in [oldCache, foreign, unknown] { try manager.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path) }
let symlink = cache.appendingPathComponent("external")
try manager.createSymbolicLink(at: symlink, withDestinationURL: foreign)
TempCleaner.sweep(in: root)
check(!manager.fileExists(atPath: oldCache.path), "expired owned cache removed")
check(manager.fileExists(atPath: recentCache.path), "fresh cache retained")
check(manager.fileExists(atPath: foreign.path), "another app's download retained")
check(manager.fileExists(atPath: unknown.path), "unknown staging file retained")
check(manager.fileExists(atPath: symlink.path), "symlink target untouched")

let suiteName = "DropDrive.MediaHarness." + UUID().uuidString
let defaults = UserDefaults(suiteName: suiteName)!
defer { defaults.removePersistentDomain(forName: suiteName) }
let tiktok = "https://www.tiktok.com/@creator/video/1234567890123456789"
VideoDownloadPolicy.saveQuality(.mp3, for: tiktok, defaults: defaults)
check(VideoDownloadPolicy.savedQuality(for: "https://vm.tiktok.com/abc", defaults: defaults) == .mp3, "TikTok share links remember MP3")
check(VideoDownloadPolicy.savedQuality(for: "https://youtu.be/abc", defaults: defaults) == .automatic, "YouTube choice independent")
VideoDownloadPolicy.saveQuality(.small, for: tiktok, defaults: defaults)
VideoDownloadPolicy.saveQuality(.mp3, for: tiktok, defaults: defaults)
check(VideoDownloadPolicy.savedVideoQuality(for: tiktok, defaults: defaults) == .small, "MP3 choice retains previous video quality")
check(VideoDownloadPolicy.platform(for: "https://tiktok.com.attacker.test/") == nil, "lookalike source rejected")
check(VideoDownloadPolicy.rateArguments(1024) == ["--limit-rate", "1024"], "video receives rate limit")
check(VideoDownloadPolicy.rateArguments(.nan).isEmpty, "invalid rate ignored")
check(VideoDownloadPolicy.failure(for: "ERROR: connection reset by peer") == .network, "transient network error retries")
check(VideoDownloadPolicy.failure(for: "ERROR: No space left on device") == .space, "disk full stays actionable")
check(VideoDownloadPolicy.failure(for: "ERROR: Private video. Sign in") == .authentication, "private media keeps access failure")

let neverStarted = Process()
neverStarted.executableURL = URL(fileURLWithPath: "/bin/sleep")
neverStarted.arguments = ["30"]
let lifetime = VideoProcessLifetime(neverStarted)
lifetime.cancel()
do { try lifetime.start(); fatalError("cancelled process launched") }
catch is CancellationError { print("PASS: cancel before process launch") }

let destination = root.appendingPathComponent("destination")
try manager.createDirectory(at: destination, withIntermediateDirectories: true)
let guarded = Task {
    try await TransferGuard.run(destination: destination) {
        try await Task.sleep(for: .seconds(30))
        return true
    }
}
try await Task.sleep(for: .milliseconds(100))
try manager.removeItem(at: destination)
do { _ = try await guarded.value; fatalError("removed destination accepted") }
catch VideoDownloadPolicy.Failure.destination { print("PASS: disconnected destination cancels transfer") }

if CommandLine.arguments.contains("--fake-extractor") {
    let service = VideoDownloadService()
    let outputFolder = root.appendingPathComponent("fake-outputs")
    try manager.createDirectory(at: outputFolder, withIntermediateDirectories: true)
    for link in ["https://www.youtube.com/watch?v=fixture", "https://www.instagram.com/p/fixture", "https://www.facebook.com/watch/?v=123"] {
        let source = VideoDownloadPolicy.platform(for: link)!
        let analysis = try await service.analyze(link)
        check(analysis.name == "Source fixture", "\(source) full analysis fallback")
        do {
            _ = try await service.download(link: link, title: analysis.name, destination: outputFolder, onProgress: { _ in })
            fatalError("fixture should fail")
        } catch let error as VideoDownloadService.VideoError {
            check(error.message.contains("503"), "\(source) preserves original error instead of watermark message")
            check(error.failure == .network, "\(source) transient failure stays retryable")
        }
    }
}

if CommandLine.arguments.contains("--live-tiktok") {
    // Read only a previously used public source, never credentials or filenames.
    let appDefaults = UserDefaults(suiteName: "com.dropdrive.DropDrive")!
    guard let data = appDefaults.data(forKey: "downloadHistory"),
          let history = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
          let link = history.compactMap({ $0["driveLink"] as? String }).first(where: { VideoDownloadPolicy.platform(for: $0) == "tiktok" })
    else { fatalError("No TikTok fixture in history") }
    let service = VideoDownloadService()
    guard let analysis = await service.quickAnalyze(link) else { fatalError("TikTok metadata unavailable") }
    let outputFolder = root.appendingPathComponent("outputs")
    try manager.createDirectory(at: outputFolder, withIntermediateDirectories: true)
    let start = Date()
    let output = try await service.download(link: link, title: analysis.name, destination: outputFolder,
        asAudio: true, clipSection: "0-3", customName: "Review audio", quality: .mp3,
        thumbnailURL: analysis.thumbnailURL, ownerName: analysis.ownerName, onProgress: { _ in })
    let asset = AVURLAsset(url: output)
    let duration = try await asset.load(.duration).seconds
    let metadata = try await asset.load(.commonMetadata)
    check(output.pathExtension == "mp3", "actual service creates MP3")
    check(duration > 2 && duration < 4.5, "actual MP3 trim respected")
    check(metadata.contains { $0.commonKey == .commonKeyTitle }, "MP3 retains title tag")
    if analysis.thumbnailURL != nil {
        check(metadata.contains { $0.commonKey == .commonKeyArtwork }, "MP3 retains artwork")
    }
    print(String(format: "LIVE TikTok trimmed MP3 completed in %.2fs", Date().timeIntervalSince(start)))
    let cancelFolder = root.appendingPathComponent("cancel")
    try manager.createDirectory(at: cancelFolder, withIntermediateDirectories: true)
    let transfer = Task {
        try await service.download(link: link, title: analysis.name, destination: cancelFolder,
            asAudio: true, customName: "Cancelled audio", quality: .mp3, onProgress: { _ in })
    }
    try await Task.sleep(for: .seconds(2))
    transfer.cancel()
    do { _ = try await transfer.value; fatalError("cancelled download completed") }
    catch is CancellationError { print("PASS: live TikTok cancellation returns cancellation") }
}
print("ALL PASS")

import Foundation

final class PeakCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var live = 0
    private(set) var peak = 0

    func enter() {
        lock.lock()
        live += 1
        peak = max(peak, live)
        lock.unlock()
    }

    func leave() {
        lock.lock()
        live -= 1
        lock.unlock()
    }
}

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    print("\(condition ? "PASS" : "FAIL") \(label)\(detail.isEmpty ? "" : ": \(detail)")")
    if !condition { failures += 1 }
}

let counter = PeakCounter()
let start = Date()
let output = await BoundedAsyncMap.run(Array(0..<8), limit: 4) { value in
    counter.enter()
    try? await Task.sleep(for: .milliseconds(100))
    counter.leave()
    return value * 2
}
let elapsed = Date().timeIntervalSince(start)

check("batch analysis preserves input order", output == Array(0..<8).map { $0 * 2 })
check("batch analysis respects its request cap", counter.peak == 4, "peak \(counter.peak)")
check("eight analyses finish in two waves", elapsed < 0.45, String(format: "%.2fs", elapsed))

let youtubeA = LinkIdentity.videoItemID(for: "https://www.youtube.com/watch?v=abc123&utm_source=chat")
let youtubeB = LinkIdentity.videoItemID(for: "https://youtu.be/abc123?si=tracking")
check("YouTube share variants deduplicate", youtubeA == youtubeB, youtubeA)

let instagramA = LinkIdentity.videoItemID(for: "https://www.instagram.com/reel/XYZ987/?utm_medium=copy_link")
let instagramB = LinkIdentity.videoItemID(for: "https://instagram.com/reel/XYZ987/")
check("Instagram tracking links deduplicate", instagramA == instagramB, instagramA)

let tiktokA = LinkIdentity.videoItemID(for: "https://www.tiktok.com/@creator/video/1234567890123456789?share_id=1")
let tiktokB = LinkIdentity.videoItemID(for: "https://m.tiktok.com/@creator/video/1234567890123456789")
check("TikTok mobile links deduplicate", tiktokA == tiktokB, tiktokA)

if failures > 0 { exit(1) }
print("ALL PASS")

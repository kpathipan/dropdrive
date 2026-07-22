import Foundation

/// Process-wide token-bucket throttle shared by every concurrent connection (a single
/// file's stream, or a multi-part file's several ranged streams). Called synchronously
/// from URLSession delegate callbacks, so it sleeps the calling thread directly rather
/// than hopping through async/await — the delegate queue is serial, so blocking it here
/// genuinely throttles further reads instead of just under-reporting progress.
// `nonisolated` on the type: every caller is a URLSession delegate callback on
// a background queue, and `throttle` deliberately sleeps the calling thread.
// Left implicitly MainActor-isolated (this project's default), the annotation
// claimed the opposite of how it runs — and any future main-thread caller would
// have frozen the UI for the sleep.
nonisolated final class BandwidthLimiter: @unchecked Sendable {
    static let shared = BandwidthLimiter()

    private let lock = NSLock()
    /// Bytes per second; nil means unlimited.
    private var limit: Double?
    private var windowStart = Date()
    private var bytesInWindow: Int64 = 0

    private init() {}

    func setLimit(bytesPerSecond: Double?) {
        lock.lock()
        defer { lock.unlock() }
        limit = bytesPerSecond
        windowStart = Date()
        bytesInWindow = 0
    }

    /// Records `count` freshly-received bytes and blocks the calling thread just long
    /// enough to keep the trailing-second rate at or below the configured limit.
    func throttle(bytes count: Int64) {
        lock.lock()
        guard let limit, limit > 0 else {
            lock.unlock()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(windowStart)
        if elapsed >= 1.0 {
            windowStart = now
            bytesInWindow = 0
        }

        bytesInWindow += count
        let allowedByNow = limit * max(0, now.timeIntervalSince(windowStart))
        let overage = Double(bytesInWindow) - allowedByNow
        lock.unlock()

        guard overage > 0 else { return }
        let sleepInterval = min(overage / limit, 1.0)
        guard sleepInterval > 0 else { return }
        Thread.sleep(forTimeInterval: sleepInterval)
    }
}

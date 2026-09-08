import Foundation

/// Serialize launch/cancel so cancellation before Process.run cannot be lost.
/// SIGINT lets yt-dlp close its active downloader (including ffmpeg) and partials.
nonisolated final class VideoProcessLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var cancelled = false
    init(_ process: Process) { self.process = process }
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
    func start() throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        try process.run()
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if process.isRunning { process.interrupt() }
    }
}

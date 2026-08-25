import Foundation

/// Formatter instances are expensive to build and these run on every progress
/// tick, for every visible row — `ByteCountFormatter.string(fromByteCount:…)`
/// and a fresh `DateComponentsFormatter` were each constructing one from
/// scratch several times a second. They're held here instead, behind a lock
/// because Foundation's formatters aren't thread-safe and progress text is
/// built from more than one context.
enum Formatters {
    private nonisolated(unsafe) static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private nonisolated static let shortDuration: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    private nonisolated static let longDuration: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    private nonisolated static let lock = NSLock()

    nonisolated static func byteCount(_ bytes: Int64) -> String {
        // ByteCountFormatter spells this as "Zero KB" in some locales, which
        // leaks English into an otherwise Thai screen and is visually noisier
        // than the numeric form used for every non-zero value.
        if bytes == 0 { return "0 KB" }
        lock.lock()
        defer { lock.unlock() }
        return byteFormatter.string(fromByteCount: bytes)
    }

    nonisolated static func transferSpeed(_ bytesPerSecond: Double) -> String {
        "\(byteCount(Int64(bytesPerSecond)))/s"
    }

    static func remainingTime(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        lock.lock()
        let text = (seconds >= 3600 ? longDuration : shortDuration).string(from: seconds)
        lock.unlock()
        return text.map { tr("\($0) remaining", "เหลืออีก \($0)") }
    }
}

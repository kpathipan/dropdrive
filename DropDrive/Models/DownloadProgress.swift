import Foundation

struct DownloadProgress: Equatable, Sendable {
    var currentFileName: String = ""
    var completedFiles: Int = 0
    var totalFiles: Int = 0
    var bytesDownloaded: Int64 = 0
    var totalBytes: Int64 = 0
    var bytesPerSecond: Double = 0

    var fractionCompleted: Double? {
        if totalBytes > 0 {
            return min(1, max(0, Double(bytesDownloaded) / Double(totalBytes)))
        }
        if totalFiles > 0 {
            return min(1, max(0, Double(completedFiles) / Double(totalFiles)))
        }
        return nil
    }

    /// Progress shown while the item is still active. Rounding 99.5% to 100%
    /// made the app claim completion while it was still flushing, validating,
    /// or finishing another fragment. The completed queue state owns 100%; an
    /// active transfer can get arbitrarily close, but never display it.
    var activeDisplayPercentage: Int? {
        fractionCompleted.map { min(99, max(0, Int(($0 * 100).rounded(.down)))) }
    }

    var activeDisplayFraction: Double? {
        fractionCompleted.map { min(0.99, max(0, $0)) }
    }

    var etaSeconds: Double? {
        guard bytesPerSecond > 0, totalBytes > bytesDownloaded else { return nil }
        return Double(totalBytes - bytesDownloaded) / bytesPerSecond
    }
}

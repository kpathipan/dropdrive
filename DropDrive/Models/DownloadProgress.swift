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
            return min(1, Double(bytesDownloaded) / Double(totalBytes))
        }
        if totalFiles > 0 {
            return min(1, Double(completedFiles) / Double(totalFiles))
        }
        return nil
    }

    var etaSeconds: Double? {
        guard bytesPerSecond > 0, totalBytes > bytesDownloaded else { return nil }
        return Double(totalBytes - bytesDownloaded) / bytesPerSecond
    }

    var progressDescription: String {
        let downloaded = Formatters.byteCount(bytesDownloaded)
        let total = Formatters.byteCount(totalBytes)

        if totalBytes > 0 {
            return "\(downloaded) / \(total)"
        } else if totalFiles > 1 {
            return "\(completedFiles) / \(totalFiles) files"
        } else {
            return downloaded
        }
    }

    var estimatedTimeRemaining: String? {
        guard let seconds = etaSeconds else { return nil }
        return Formatters.remainingTime(seconds)
    }
}

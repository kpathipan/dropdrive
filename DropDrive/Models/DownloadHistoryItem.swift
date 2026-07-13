import Foundation

struct DownloadHistoryItem: Identifiable {
    enum Status {
        case completed
        case failed
        case cancelled
    }

    let id = UUID()
    let name: String
    let date: Date
    let status: Status
}

import Foundation

struct DownloadHistoryItem: Identifiable, Codable, Equatable {
    enum Status: String, Codable {
        case completed
        case failed
        case cancelled
    }

    let id: UUID
    let name: String
    let date: Date
    let status: Status
    /// The downloaded file or folder on disk. Only present for completed downloads.
    let itemURL: URL?
    /// The original Google Drive link, kept so the user can retry or share it later.
    let driveLink: String

    init(id: UUID = UUID(), name: String, date: Date, status: Status, itemURL: URL? = nil, driveLink: String) {
        self.id = id
        self.name = name
        self.date = date
        self.status = status
        self.itemURL = itemURL
        self.driveLink = driveLink
    }
}

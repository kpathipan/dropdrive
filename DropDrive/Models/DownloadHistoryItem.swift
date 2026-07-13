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
    /// Number of files this entry represents (1 for a single file). Known from the
    /// Drive analysis at completion time, not a filesystem walk. Absent on entries
    /// recorded before this field existed.
    let fileCount: Int?
    /// Total size in bytes, from the same analysis. Absent on older entries or when
    /// Drive didn't report a size.
    let sizeBytes: Int64?

    init(
        id: UUID = UUID(),
        name: String,
        date: Date,
        status: Status,
        itemURL: URL? = nil,
        driveLink: String,
        fileCount: Int? = nil,
        sizeBytes: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.status = status
        self.itemURL = itemURL
        self.driveLink = driveLink
        self.fileCount = fileCount
        self.sizeBytes = sizeBytes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, date, status, itemURL, driveLink, fileCount, sizeBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        date = try container.decode(Date.self, forKey: .date)
        status = try container.decode(Status.self, forKey: .status)
        itemURL = try container.decodeIfPresent(URL.self, forKey: .itemURL)
        driveLink = try container.decode(String.self, forKey: .driveLink)
        fileCount = try container.decodeIfPresent(Int.self, forKey: .fileCount)
        sizeBytes = try container.decodeIfPresent(Int64.self, forKey: .sizeBytes)
    }
}

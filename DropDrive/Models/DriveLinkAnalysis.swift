import Foundation

struct DriveLinkAnalysis: Equatable, Sendable, Codable {
    enum ItemType: String, Equatable, Sendable, Codable {
        case file
        case folder
    }

    /// File-type breakdown for a folder's contents, gathered during the same recursive
    /// scan used for size/file count — no extra API calls. Only populated for folders.
    struct CategoryBreakdown: Equatable, Sendable, Codable {
        var images = 0
        var videos = 0
        var documents = 0
        var archives = 0
        var other = 0

        var isEmpty: Bool {
            images == 0 && videos == 0 && documents == 0 && archives == 0 && other == 0
        }
    }

    let itemID: String
    let name: String
    let type: ItemType
    let isPublic: Bool
    let requiresAuthentication: Bool
    let totalBytes: Int64?
    let fileCount: Int?
    let ownerName: String?
    let categoryBreakdown: CategoryBreakdown?
    /// True for a TikTok/YouTube/Facebook link handled by the yt-dlp engine.
    /// Optional so queue items persisted by older versions still decode.
    var isVideo: Bool?

    init(
        itemID: String,
        name: String,
        type: ItemType,
        isPublic: Bool,
        requiresAuthentication: Bool,
        totalBytes: Int64?,
        fileCount: Int?,
        ownerName: String?,
        categoryBreakdown: CategoryBreakdown?,
        isVideo: Bool? = nil
    ) {
        self.itemID = itemID
        self.name = name
        self.type = type
        self.isPublic = isPublic
        self.requiresAuthentication = requiresAuthentication
        self.totalBytes = totalBytes
        self.fileCount = fileCount
        self.ownerName = ownerName
        self.categoryBreakdown = categoryBreakdown
        self.isVideo = isVideo
    }
}

enum LinkAnalysisResult: Equatable, Sendable {
    case success(DriveLinkAnalysis)
    case needsAuthentication
}

enum LinkAnalysisState: Equatable {
    case idle
    case invalidLink
    case analyzing
    case needsConnection
    case failed(String)
    /// Analysis succeeded; showing the result card and waiting for the user to
    /// confirm (and to pick a destination first if they want) before anything is
    /// queued. Auto-queueing here used to clear the link field the moment
    /// analysis finished, which read as "the download button doesn't work" and
    /// froze the destination before the user could change it.
    case analyzed(DriveLinkAnalysis)
    /// The link's item ID matches a non-completed item already in the queue.
    case duplicateActive
    /// The link's item ID matches an item that already completed this session;
    /// asks the user whether to queue it again.
    case duplicateCompleted(DriveLinkAnalysis)
}

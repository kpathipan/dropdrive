import Foundation

nonisolated struct DriveLinkAnalysis: Equatable, Sendable, Codable {
    nonisolated enum ItemType: String, Equatable, Sendable, Codable {
        case file
        case folder
    }

    /// File-type breakdown for a folder's contents, gathered during the same recursive
    /// scan used for size/file count — no extra API calls. Only populated for folders.
    nonisolated struct CategoryBreakdown: Equatable, Sendable, Codable {
        var images = 0
        var videos = 0
        var documents = 0
        var archives = 0
        var other = 0

        var isEmpty: Bool {
            images == 0 && videos == 0 && documents == 0 && archives == 0 && other == 0
        }
    }

    /// A downloadable file discovered while the folder is already being scanned
    /// for size. Keeping this manifest in memory lets the review card select
    /// files without a second Drive walk and lets disk-space checks use the
    /// selected bytes rather than the entire folder.
    nonisolated struct FolderItem: Identifiable, Equatable, Sendable, Codable {
        enum Category: String, Equatable, Sendable, Codable, CaseIterable {
            case images, videos, documents, archives, other
        }

        let id: String
        let name: String
        let relativePath: String
        let mimeType: String
        let size: Int64?
        let category: Category
        let resourceKey: String?
        let md5Checksum: String?

        init(
            id: String,
            name: String,
            relativePath: String,
            mimeType: String,
            size: Int64?,
            category: Category,
            resourceKey: String? = nil,
            md5Checksum: String? = nil
        ) {
            self.id = id
            self.name = name
            self.relativePath = relativePath
            self.mimeType = mimeType
            self.size = size
            self.category = category
            self.resourceKey = resourceKey
            self.md5Checksum = md5Checksum
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
    var folderItems: [FolderItem]?
    /// True for a TikTok/YouTube/Facebook link handled by the yt-dlp engine.
    /// Optional so queue items persisted by older versions still decode.
    var isVideo: Bool?
    /// Video links only: poster image and duration from the extractor, for the
    /// confirm card's preview and the trim field hints.
    var thumbnailURL: String?
    var durationSeconds: Double?

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
        folderItems: [FolderItem]? = nil,
        isVideo: Bool? = nil,
        thumbnailURL: String? = nil,
        durationSeconds: Double? = nil
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
        self.folderItems = folderItems
        self.isVideo = isVideo
        self.thumbnailURL = thumbnailURL
        self.durationSeconds = durationSeconds
    }

    /// Returns the same analysis narrowed to the selected folder files. Nil
    /// means "all files"; an empty set is a valid zero-file selection that the
    /// UI must prevent from being queued.
    func selectingFolderItems(_ selectedIDs: Set<String>?) -> DriveLinkAnalysis {
        guard type == .folder, let folderItems, let selectedIDs else { return self }
        let selected = folderItems.filter { selectedIDs.contains($0.id) }
        var breakdown = CategoryBreakdown()
        for item in selected {
            switch item.category {
            case .images: breakdown.images += 1
            case .videos: breakdown.videos += 1
            case .documents: breakdown.documents += 1
            case .archives: breakdown.archives += 1
            case .other: breakdown.other += 1
            }
        }
        var copy = self
        copy.folderItems = folderItems
        return DriveLinkAnalysis(
            itemID: copy.itemID,
            name: copy.name,
            type: copy.type,
            isPublic: copy.isPublic,
            requiresAuthentication: copy.requiresAuthentication,
            totalBytes: selected.reduce(Int64(0)) { $0 + ($1.size ?? 0) },
            fileCount: selected.count,
            ownerName: copy.ownerName,
            categoryBreakdown: breakdown,
            folderItems: folderItems,
            isVideo: copy.isVideo,
            thumbnailURL: copy.thumbnailURL,
            durationSeconds: copy.durationSeconds
        )
    }
}

nonisolated enum LinkAnalysisResult: Equatable, Sendable {
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
    /// Several pasted links are reviewed together. Each entry retains its own
    /// result so one private/bad link never hides the useful ones.
    case batchReview([BatchLinkReview])
    /// The link's item ID matches a non-completed item already in the queue.
    case duplicateActive
    /// The link's item ID matches an item that already completed this session;
    /// asks the user whether to queue it again.
    case duplicateCompleted(DriveLinkAnalysis)
}

struct BatchLinkReview: Identifiable, Equatable {
    enum Result: Equatable {
        case ready(DriveLinkAnalysis)
        case needsConnection
        case unavailable(String)
    }

    let link: String
    var isSelected: Bool
    let result: Result

    var id: String { link }
}

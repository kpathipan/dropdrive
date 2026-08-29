import Foundation

struct QueueItem: Identifiable, Equatable, Codable {
    enum Status: String, Codable, Equatable {
        case ready
        case downloading
        case completed
        case failed
        case cancelled
        case paused
        /// A recoverable interruption (network/NAS/sleep). The app owns the
        /// retry; this is surfaced separately from a terminal failure.
        case waiting
    }


    enum AttentionKind: String, Codable, Equatable {
        case network, destination, authentication, space, source
    }

    let id: UUID
    let driveLink: String
    let analysis: DriveLinkAnalysis
    var status: Status
    var resultURL: URL?
    var errorMessage: String?

    /// Captured from the "Save to" folder at the moment this item was queued, not
    /// read fresh when the download actually starts — the queue used to share one
    /// global destination that was read at start time, so changing "Save to" while
    /// something was still queued silently moved every pending item's destination,
    /// including files queued before the change. `Optional` only so a `QueueItem`
    /// persisted before this field existed still decodes; `processQueueIfNeeded`
    /// falls back to the current global destination for those.
    var destinationURL: URL?

    /// Video links only: true when the user chose MP3 (audio extraction) on the
    /// confirm card instead of the video itself. Optional for decode
    /// compatibility with queues persisted before this existed.
    var asAudio: Bool?

    /// Video links only: a "start-end" section (both in seconds) when the user
    /// trimmed the clip on the confirm card. Nil downloads the whole video.
    var clipSection: String?

    /// A name typed on the confirm card, replacing the one the link came with.
    /// The extension is never part of this — it's decided by what actually
    /// downloads — so a file keeps its real type no matter what is typed here.
    /// Nil (the common case) keeps the original name. Optional also for decode
    /// compatibility with queues persisted before this existed.
    var customName: String?
    var selectedFileIDs: Set<String>?
    var videoQuality: DriveLinkAnalysis.VideoQuality?
    var subtitleMode: DriveLinkAnalysis.SubtitleMode?
    var splitChapters: Bool?
    var saveThumbnail: Bool?
    /// 1-based extractor positions. Nil means the complete playlist/carousel.
    var selectedMediaIndexes: Set<Int>?
    var attentionKind: AttentionKind?
    var retryCount: Int?
    var nextRetryAt: Date?

    init(
        id: UUID = UUID(),
        driveLink: String,
        analysis: DriveLinkAnalysis,
        status: Status = .ready,
        resultURL: URL? = nil,
        errorMessage: String? = nil,
        destinationURL: URL? = nil,
        asAudio: Bool? = nil,
        clipSection: String? = nil,
        customName: String? = nil,
        selectedFileIDs: Set<String>? = nil,
        videoQuality: DriveLinkAnalysis.VideoQuality? = nil,
        subtitleMode: DriveLinkAnalysis.SubtitleMode? = nil,
        splitChapters: Bool? = nil,
        saveThumbnail: Bool? = nil,
        selectedMediaIndexes: Set<Int>? = nil,
        attentionKind: AttentionKind? = nil,
        retryCount: Int? = nil,
        nextRetryAt: Date? = nil
    ) {
        self.id = id
        self.driveLink = driveLink
        self.analysis = analysis
        self.status = status
        self.resultURL = resultURL
        self.errorMessage = errorMessage
        self.destinationURL = destinationURL
        self.asAudio = asAudio
        self.clipSection = clipSection
        self.customName = customName
        self.selectedFileIDs = selectedFileIDs
        self.videoQuality = videoQuality
        self.subtitleMode = subtitleMode
        self.splitChapters = splitChapters
        self.saveThumbnail = saveThumbnail
        self.selectedMediaIndexes = selectedMediaIndexes
        self.attentionKind = attentionKind
        self.retryCount = retryCount
        self.nextRetryAt = nextRetryAt
    }

    var itemID: String { analysis.itemID }

    /// What every list in the app shows for this item: the typed name when there
    /// is one, so the queue matches what will land on disk.
    var displayName: String { customName ?? analysis.name }
}

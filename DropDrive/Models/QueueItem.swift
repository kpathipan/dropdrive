import Foundation

struct QueueItem: Identifiable, Equatable, Codable {
    enum Status: String, Codable, Equatable {
        case ready
        case downloading
        case completed
        case failed
        case cancelled
        case paused
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

    init(
        id: UUID = UUID(),
        driveLink: String,
        analysis: DriveLinkAnalysis,
        status: Status = .ready,
        resultURL: URL? = nil,
        errorMessage: String? = nil,
        destinationURL: URL? = nil,
        asAudio: Bool? = nil,
        clipSection: String? = nil
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
    }

    var itemID: String { analysis.itemID }
}

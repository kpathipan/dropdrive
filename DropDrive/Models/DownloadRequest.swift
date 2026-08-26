import Foundation

nonisolated struct DownloadRequest: Equatable, Sendable {
    let driveLink: String
    let itemID: String
    let destinationURL: URL
    var resourceKey: String? = nil
    /// Identifies this download across pause/resume/retry attempts (the owning
    /// QueueItem's id), so resume data and in-progress-folder markers stay scoped
    /// to the right item.
    var resumeID: UUID = UUID()
    /// Replaces the name the item has on Drive. A file keeps its real extension
    /// (this is the base name only); a folder is created under this name.
    var customName: String? = nil
    /// Nil downloads the complete folder. A set downloads only these Drive file
    /// IDs; stored on the queue so retries and relaunches keep the same choice.
    var selectedFileIDs: Set<String>? = nil
    /// The already-analyzed selected files. When present the engine can build a
    /// folder download plan immediately instead of listing the whole Drive tree
    /// for a second time.
    var selectedFolderItems: [DriveLinkAnalysis.FolderItem]? = nil
}

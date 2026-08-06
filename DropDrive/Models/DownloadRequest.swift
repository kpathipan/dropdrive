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
}

import Foundation

struct DownloadRequest: Equatable {
    let driveLink: String
    let itemID: String
    let destinationURL: URL
    var resourceKey: String? = nil
    /// Identifies this download across pause/resume/retry attempts (the owning
    /// QueueItem's id), so resume data and in-progress-folder markers stay scoped
    /// to the right item.
    var resumeID: UUID = UUID()
}

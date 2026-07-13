import Foundation

extension QueueItem.Status {
    var displayName: String {
        switch self {
        case .ready:
            return "Waiting"
        case .downloading:
            return "Downloading"
        case .completed:
            return "Complete"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        case .paused:
            return "Paused"
        }
    }
}

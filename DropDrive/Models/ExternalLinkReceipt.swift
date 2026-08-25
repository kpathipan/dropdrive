import Foundation

/// Outcome of a phone, Services, Share-extension, or browser hand-off. Keeping
/// the categories explicit lets the iCloud inbox consume only work that is
/// safely queued or already known, while retaining transient failures to retry.
nonisolated struct ExternalLinkReceipt: Equatable, Sendable {
    var queued = 0
    var duplicates = 0
    var retryableFailures = 0
    var unsupported = 0

    var disposition: PhoneInboxDisposition {
        if retryableFailures > 0 { return .retry }
        if unsupported > 0 { return .archiveRejected }
        return .consume
    }
}

nonisolated enum PhoneInboxDisposition: Equatable, Sendable {
    case consume
    case retry
    case archiveRejected
}

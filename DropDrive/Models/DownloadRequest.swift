import Foundation

struct DownloadRequest: Equatable {
    let driveLink: String
    let itemID: String
    let destinationURL: URL
}

import Foundation

struct DownloadRequest: Equatable {
    let driveLink: String
    let folderID: String
    let destinationURL: URL
}

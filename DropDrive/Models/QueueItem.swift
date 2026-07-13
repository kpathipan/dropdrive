import Foundation

struct QueueItem: Identifiable, Equatable, Codable {
    enum Status: String, Codable, Equatable {
        case ready
        case downloading
        case completed
        case failed
        case cancelled
    }

    let id: UUID
    let driveLink: String
    let analysis: DriveLinkAnalysis
    var status: Status
    var resultURL: URL?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        driveLink: String,
        analysis: DriveLinkAnalysis,
        status: Status = .ready,
        resultURL: URL? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.driveLink = driveLink
        self.analysis = analysis
        self.status = status
        self.resultURL = resultURL
        self.errorMessage = errorMessage
    }

    var itemID: String { analysis.itemID }
}

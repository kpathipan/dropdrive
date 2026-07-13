import Foundation

struct DriveLinkAnalysis: Equatable, Sendable {
    enum ItemType: Equatable, Sendable {
        case file
        case folder
    }

    let itemID: String
    let name: String
    let type: ItemType
    let isPublic: Bool
    let requiresAuthentication: Bool
    let totalBytes: Int64?
    let fileCount: Int?
    let ownerName: String?
}

enum LinkAnalysisResult: Equatable, Sendable {
    case success(DriveLinkAnalysis)
    case needsAuthentication
}

enum LinkAnalysisState: Equatable {
    case idle
    case invalidLink
    case analyzing
    case needsConnection
    case ready(DriveLinkAnalysis)
    case failed(String)
}

import Foundation

struct DriveLinkAnalysis: Equatable {
    enum ItemType: Equatable {
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
}

enum LinkAnalysisResult: Equatable {
    case success(DriveLinkAnalysis)
    case needsAuthentication
}

enum LinkAnalysisState: Equatable {
    case idle
    case analyzing
    case needsConnection
    case ready(DriveLinkAnalysis)
    case failed(String)
}

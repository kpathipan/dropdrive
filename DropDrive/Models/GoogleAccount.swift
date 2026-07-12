import Foundation

struct GoogleAccount: Codable, Equatable {
    let userID: String
    let name: String
    let email: String
    let profileImageURL: URL?
}

import Foundation

nonisolated struct GoogleAccount: Codable, Equatable, Identifiable, Sendable {
    let userID: String
    let name: String
    let email: String
    let profileImageURL: URL?

    var id: String { userID }
}

/// The complete account state presented to the UI. OAuth sessions never live
/// here — those stay isolated per account in Keychain — so this value is safe
/// to observe and persist as display metadata.
nonisolated struct GoogleAccountSnapshot: Equatable, Sendable {
    let accounts: [GoogleAccount]
    let defaultAccountID: String?
    let reconnectAccountIDs: Set<String>

    static let empty = GoogleAccountSnapshot(
        accounts: [],
        defaultAccountID: nil,
        reconnectAccountIDs: []
    )
}

/// A short-lived access token paired with the account that owns it. Keeping the
/// ID attached prevents a later download from silently switching credentials.
nonisolated struct GoogleAccessToken: Equatable, Sendable {
    let accountID: String
    let token: String
}

nonisolated struct GoogleAccessTokenSet: Equatable, Sendable {
    let hasAccounts: Bool
    let tokens: [GoogleAccessToken]
}

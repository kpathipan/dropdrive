import Foundation

@MainActor final class LoginManager {
    static let shared = LoginManager()
    func uploadAccessToken(accountID: String, forceRefresh: Bool) async throws -> GoogleAccessToken {
        fatalError("Offline upload tests must inject fixture tokens; no real credentials are read.")
    }
}

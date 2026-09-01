import Foundation

// Stand-ins for the app-only dependencies DownloadService.swift refers to, so
// the real file can be compiled and exercised outside the app bundle.

struct GoogleAccount: Sendable { let userID: String; let name = ""; let email = "" }
struct GoogleAccountSnapshot: Sendable {
    let accounts: [GoogleAccount]
    let defaultAccountID: String?
    let reconnectAccountIDs: Set<String>
}
struct GoogleAccessToken: Sendable { let accountID: String; let token: String }
struct GoogleAccessTokenSet: Sendable { let hasAccounts: Bool; let tokens: [GoogleAccessToken] }

protocol LoginManaging: Sendable {
    func restoreSavedAccounts() async -> GoogleAccountSnapshot
    func refreshSavedAccounts() async -> GoogleAccountSnapshot
    func signIn() async throws -> GoogleAccountSnapshot
    func removeAccount(userID: String) -> GoogleAccountSnapshot
    func setDefaultAccount(userID: String) -> GoogleAccountSnapshot
    func validAccessToken(for accountID: String?) async throws -> GoogleAccessToken
    func cachedAccessTokens(preferredAccountID: String?) async -> GoogleAccessTokenSet
}

struct StubLogin: LoginManaging {
    var tokens = [GoogleAccessToken(accountID: "account-1", token: "test-token")]
    private var snapshot: GoogleAccountSnapshot {
        GoogleAccountSnapshot(
            accounts: tokens.map { GoogleAccount(userID: $0.accountID) },
            defaultAccountID: tokens.first?.accountID,
            reconnectAccountIDs: []
        )
    }
    func restoreSavedAccounts() async -> GoogleAccountSnapshot { snapshot }
    func refreshSavedAccounts() async -> GoogleAccountSnapshot { snapshot }
    func signIn() async throws -> GoogleAccountSnapshot { snapshot }
    func removeAccount(userID: String) -> GoogleAccountSnapshot { snapshot }
    func setDefaultAccount(userID: String) -> GoogleAccountSnapshot { snapshot }
    func validAccessToken(for accountID: String?) async throws -> GoogleAccessToken { tokens.first! }
    func cachedAccessTokens(preferredAccountID: String?) async -> GoogleAccessTokenSet {
        var ordered = tokens
        if let preferredAccountID, let index = ordered.firstIndex(where: { $0.accountID == preferredAccountID }) {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        return GoogleAccessTokenSet(hasAccounts: !tokens.isEmpty, tokens: ordered)
    }
}

func tr(_ english: String, _ thai: String) -> String { english }

nonisolated final class BandwidthLimiter: @unchecked Sendable {
    static let shared = BandwidthLimiter()
    func throttle(bytes count: Int64) {}
}

// MARK: - Test-only seam
//
// The download path deliberately builds its own `URLSession(configuration:
// .ephemeral, delegate:)` per transfer, which `URLProtocol.registerClass` does
// not reach. Swizzling the ephemeral-configuration factory is how the harness
// gets its stub protocol in front of those internal sessions. Harness only —
// nothing in the app does this.
import ObjectiveC

enum EphemeralConfigPatch {
    nonisolated(unsafe) static var protocolClass: AnyClass?

    static func install() {
        let cls: AnyClass = URLSessionConfiguration.self
        let selector = Selector(("ephemeralSessionConfiguration"))
        guard let original = class_getClassMethod(cls, selector),
              let replacement = class_getClassMethod(cls, #selector(URLSessionConfiguration.harness_ephemeral)) else {
            fatalError("could not find ephemeralSessionConfiguration")
        }
        method_exchangeImplementations(original, replacement)
    }
}

extension URLSessionConfiguration {
    @objc class func harness_ephemeral() -> URLSessionConfiguration {
        // Swizzled: this call reaches the real implementation.
        let config = harness_ephemeral()
        if let stub = EphemeralConfigPatch.protocolClass {
            config.protocolClasses = [stub]
        }
        return config
    }
}

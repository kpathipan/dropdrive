import Foundation

// Stand-ins for the app-only dependencies DownloadService.swift refers to, so
// the real file can be compiled and exercised outside the app bundle.

struct GoogleAccount: Sendable { let name = ""; let email = "" }

protocol LoginManaging: Sendable {
    func restoreSavedAccount() async -> GoogleAccount?
    func signIn() async throws -> GoogleAccount
    func signOut()
    func handleCallbackURL(_ url: URL) -> Bool
    func validAccessToken() async throws -> String
    func cachedAccessTokenIfAvailable() async -> String?
}

struct StubLogin: LoginManaging {
    func restoreSavedAccount() async -> GoogleAccount? { nil }
    func signIn() async throws -> GoogleAccount { GoogleAccount() }
    func signOut() {}
    func handleCallbackURL(_ url: URL) -> Bool { false }
    func validAccessToken() async throws -> String { "test-token" }
    func cachedAccessTokenIfAvailable() async -> String? { "test-token" }
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

import AppKit
import AppAuth
import Foundation
import GTMAppAuth

protocol LoginManaging {
    func restoreSavedAccount() async -> GoogleAccount?
    func signIn() async throws -> GoogleAccount
    func signOut()
    func handleCallbackURL(_ url: URL) -> Bool
    func validAccessToken() async throws -> String
    func cachedAccessTokenIfAvailable() async -> String?
}

/// Talks to AppAuth + GTMAppAuth directly rather than going through `GIDSignIn`.
///
/// `GIDSignIn` hard-codes a `GTMKeychainStore` that writes to the *data-protection*
/// keychain (it sets `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, which forces
/// `kSecUseDataProtectionKeychain`). On macOS that keychain requires an
/// `application-identifier` entitlement, which only a real Apple Team signature
/// provides — an ad-hoc signed build has no team, so every write fails with
/// `errSecMissingEntitlement` (-34018) and GID surfaces it as "keychain error" (-2),
/// killing sign-in the instant the OAuth redirect succeeds. Verified directly: an
/// ad-hoc signed binary gets -34018 from the data-protection keychain and
/// `errSecSuccess` from the file-based one. There is no public GID API to swap the
/// store (`sharedInstance` builds its own, and `init` is `NS_UNAVAILABLE`), so this
/// drives the same underlying libraries itself and asks for the file-based keychain,
/// which needs no entitlement.
@MainActor
final class LoginManager: LoginManaging {
    static let shared = LoginManager()

    static let driveReadonlyScope = "https://www.googleapis.com/auth/drive.readonly"

    private enum StorageKey {
        static let googleAccount = "googleAccount"
    }

    private static let keychainItemName = "DropDriveAuthSession"
    private static let userInfoEndpoint = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!

    private let userDefaults: UserDefaults

    /// `.useFileBasedKeychain` is the whole point — see the type-level note above.
    private let keychainStore = KeychainStore(
        itemName: LoginManager.keychainItemName,
        keychainAttributes: [.useFileBasedKeychain]
    )

    /// AppAuth hands back a session object that the redirect has to be fed into;
    /// held here so `handleCallbackURL(_:)` can resume the in-flight flow.
    private var currentAuthorizationFlow: OIDExternalUserAgentSession?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Session lookup

    func restoreSavedAccount() async -> GoogleAccount? {
        guard let session = loadSession(), session.authState.isAuthorized else {
            // Only surface "connected" when a real session actually exists. Returning
            // the UserDefaults-cached account regardless (the old behaviour) let the
            // account chip claim signed-in while every private-file analysis still
            // failed with "needs authentication".
            userDefaults.removeObject(forKey: StorageKey.googleAccount)
            return nil
        }

        if let cached = loadStoredAccount() {
            return cached
        }

        guard let token = try? await accessToken(for: session),
              let account = try? await Self.fetchProfile(accessToken: token) else {
            return nil
        }
        save(account)
        return account
    }

    func signIn() async throws -> GoogleAccount {
        guard let clientID = configuredClientID else {
            throw LoginManagerError.missingClientID
        }
        guard let presentingWindow = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
            throw LoginManagerError.missingPresentingWindow
        }
        guard let redirectURL = Self.redirectURL(clientID: clientID) else {
            throw LoginManagerError.missingClientID
        }

        let request = OIDAuthorizationRequest(
            configuration: Self.googleConfiguration,
            clientId: clientID,
            clientSecret: nil,
            scopes: [OIDScopeOpenID, OIDScopeProfile, OIDScopeEmail, Self.driveReadonlyScope],
            redirectURL: redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )

        let authState = try await presentAuthorization(request: request, window: presentingWindow)

        let session = AuthSession(authState: authState)
        try keychainStore.save(authSession: session)

        let token = try await accessToken(for: session)
        let account = try await Self.fetchProfile(accessToken: token)
        save(account)
        return account
    }

    func signOut() {
        try? keychainStore.removeAuthSession()
        userDefaults.removeObject(forKey: StorageKey.googleAccount)
    }

    /// Only relevant if AppAuth falls back to the system browser — on macOS 10.15+
    /// it presents an `ASWebAuthenticationSession`, which captures the redirect
    /// itself without the URL ever reaching the app.
    ///
    /// AppAuth deprecates this in favour of `resumeExternalUserAgentFlowWithURL:error:`,
    /// but both selectors import into Swift under the same name and the deprecated
    /// one wins, so the replacement isn't callable from Swift at all.
    func handleCallbackURL(_ url: URL) -> Bool {
        guard let flow = currentAuthorizationFlow, flow.resumeExternalUserAgentFlow(with: url) else {
            return false
        }
        currentAuthorizationFlow = nil
        return true
    }

    // MARK: - Tokens

    /// Returns a valid access token only if a stored session already carries the
    /// required scope, refreshing silently if needed. Never prompts for interaction.
    func cachedAccessTokenIfAvailable() async -> String? {
        guard let session = loadSession(), session.authState.isAuthorized else {
            return nil
        }

        let scopes = Self.grantedScopes(of: session)
        guard scopes.contains(Self.driveReadonlyScope) else {
            return nil
        }

        return try? await accessToken(for: session)
    }

    func validAccessToken() async throws -> String {
        guard let session = loadSession(), session.authState.isAuthorized else {
            throw LoginManagerError.notSignedIn
        }
        guard Self.grantedScopes(of: session).contains(Self.driveReadonlyScope) else {
            // AppAuth has no incremental-scope call; sign-in already requests the
            // Drive scope, so a session without it means re-authorizing from scratch.
            throw LoginManagerError.notSignedIn
        }
        return try await accessToken(for: session)
    }

    /// Refreshes the access token if it has expired, then re-persists the session —
    /// a refresh can rotate the refresh token, and dropping that would silently
    /// invalidate the stored session on the next launch.
    private func accessToken(for session: AuthSession) async throws -> String {
        let token: String = try await withCheckedThrowingContinuation { continuation in
            session.authState.performAction { accessToken, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let accessToken else {
                    continuation.resume(throwing: LoginManagerError.missingAccessToken)
                    return
                }
                continuation.resume(returning: accessToken)
            }
        }
        try? keychainStore.save(authSession: session)
        return token
    }

    // MARK: - AppAuth plumbing

    private static let googleConfiguration = OIDServiceConfiguration(
        authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
    )

    private func presentAuthorization(
        request: OIDAuthorizationRequest,
        window: NSWindow
    ) async throws -> OIDAuthState {
        // AppAuth's `OIDAuthState` isn't Sendable, and it comes back through a
        // completion handler, so it stays boxed across the continuation and is
        // only unwrapped here on the main actor.
        let boxed: UncheckedSendable<OIDAuthState> = try await withCheckedThrowingContinuation { continuation in
            currentAuthorizationFlow = OIDAuthState.authState(
                byPresenting: request,
                presenting: window
            ) { authState, error in
                if let authState {
                    continuation.resume(returning: UncheckedSendable(authState))
                } else {
                    continuation.resume(throwing: error ?? LoginManagerError.notSignedIn)
                }
            }
        }
        return boxed.value
    }

    private func loadSession() -> AuthSession? {
        try? keychainStore.retrieveAuthSession()
    }

    private static func grantedScopes(of session: AuthSession) -> [String] {
        let scope = session.authState.lastTokenResponse?.scope
            ?? session.authState.lastAuthorizationResponse.scope
        return scope?.components(separatedBy: " ") ?? []
    }

    private static func fetchProfile(accessToken: String) async throws -> GoogleAccount {
        struct UserInfo: Decodable {
            let sub: String
            let name: String?
            let email: String?
            let picture: String?
        }

        var request = URLRequest(url: userInfoEndpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LoginManagerError.missingAccessToken
        }
        let info = try JSONDecoder().decode(UserInfo.self, from: data)
        return GoogleAccount(
            userID: info.sub,
            name: info.name ?? "Google User",
            email: info.email ?? "No email available",
            profileImageURL: info.picture.flatMap(URL.init(string:))
        )
    }

    // MARK: - Configuration

    private var configuredClientID: String? {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty,
              !clientID.contains("YOUR_") else {
            return nil
        }
        return clientID
    }

    /// Google's installed-app redirect is the reversed client ID, which is also the
    /// URL scheme already registered in Info.plist.
    private static func redirectURL(clientID: String) -> URL? {
        let reversed = Bundle.main.object(forInfoDictionaryKey: "REVERSED_CLIENT_ID") as? String
            ?? "com.googleusercontent.apps." + clientID.replacingOccurrences(
                of: ".apps.googleusercontent.com",
                with: ""
            )
        return URL(string: "\(reversed):/oauthredirect")
    }

    // MARK: - Cached profile

    private func save(_ account: GoogleAccount) {
        guard let data = try? JSONEncoder().encode(account) else {
            return
        }
        userDefaults.set(data, forKey: StorageKey.googleAccount)
    }

    private func loadStoredAccount() -> GoogleAccount? {
        guard let data = userDefaults.data(forKey: StorageKey.googleAccount) else {
            return nil
        }
        return try? JSONDecoder().decode(GoogleAccount.self, from: data)
    }
}

enum LoginManagerError: LocalizedError {
    case missingClientID
    case missingPresentingWindow
    case notSignedIn
    case missingAccessToken

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            "Set GIDClientID and the reversed client ID URL scheme before signing in."
        case .missingPresentingWindow:
            "A presentation window was not available for Google Sign-In."
        case .notSignedIn:
            "Sign in with Google before downloading."
        case .missingAccessToken:
            "Could not obtain a valid Google access token."
        }
    }
}

/// Carries a value across an isolation boundary the compiler can't verify.
/// Used where a callback-based API hands back a non-Sendable object it has
/// already finished with.
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

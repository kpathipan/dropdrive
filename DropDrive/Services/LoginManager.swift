import AppKit
import AppAuth
import Foundation
import GTMAppAuth

/// The download engine calls this from nonisolated work, while the concrete
/// manager stays on MainActor because AppAuth presents UI and owns mutable auth
/// state. Every returned token remains paired with its Google subject ID.
protocol LoginManaging: Sendable {
    func restoreSavedAccounts() async -> GoogleAccountSnapshot
    func refreshSavedAccounts() async -> GoogleAccountSnapshot
    func signIn() async throws -> GoogleAccountSnapshot
    func removeAccount(userID: String) -> GoogleAccountSnapshot
    func setDefaultAccount(userID: String) -> GoogleAccountSnapshot
    func validAccessToken(for accountID: String?) async throws -> GoogleAccessToken
    func cachedAccessTokens(preferredAccountID: String?) async -> GoogleAccessTokenSet
}

/// Multi-account Google OAuth backed by one file-based Keychain item per user.
///
/// The file-based store is intentional. GoogleSignIn's data-protection store
/// needs an application-identifier entitlement, which free/ad-hoc macOS builds
/// cannot supply. Separate item names let several refresh tokens coexist and
/// ensure removing one account never rewrites another account's ACL.
@MainActor
final class LoginManager: LoginManaging {
    static let shared = LoginManager()

    static let driveReadonlyScope = "https://www.googleapis.com/auth/drive.readonly"

    private enum StorageKey {
        /// Pre-multi-account display metadata, retained only for migration.
        static let legacyGoogleAccount = "googleAccount"
        static let accounts = "googleAccounts.v2"
        static let defaultAccountID = "defaultGoogleAccountID.v2"
    }

    private static let userInfoEndpoint = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!

    private let userDefaults: UserDefaults
    private let legacyKeychainStore = KeychainStore(
        itemName: KeychainNamespace.sessionItem,
        keychainAttributes: [.useFileBasedKeychain]
    )

    /// Retained until ASWebAuthenticationSession captures its callback.
    private var currentAuthorizationFlow: OIDExternalUserAgentSession?
    /// Fresh OAuth sessions stay live here so analysis never depends on an
    /// immediate Keychain read-after-write. Keychain remains durable storage.
    private var activeSessions: [String: AuthSession] = [:]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Account lifecycle

    func restoreSavedAccounts() async -> GoogleAccountSnapshot {
        migrateLegacySessionIfPresent()
        return currentSnapshot()
    }

    func refreshSavedAccounts() async -> GoogleAccountSnapshot {
        migrateLegacySessionIfPresent()
        var accounts = loadStoredAccounts()
        var reconnectIDs: Set<String> = []

        for index in accounts.indices {
            let accountID = accounts[index].userID
            guard let session = loadSession(for: accountID),
                  session.authState.isAuthorized,
                  Self.grantedScopes(of: session).contains(Self.driveReadonlyScope),
                  let token = try? await accessToken(for: session, accountID: accountID) else {
                reconnectIDs.insert(accountID)
                continue
            }
            if let fresh = try? await Self.fetchProfile(accessToken: token), fresh.userID == accountID {
                accounts[index] = fresh
            }
        }

        saveAccounts(accounts)
        return snapshot(accounts: accounts, reconnectIDs: reconnectIDs)
    }

    func signIn() async throws -> GoogleAccountSnapshot {
        guard let clientID = configuredClientID else { throw LoginManagerError.missingClientID }
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
            // Without Google's chooser, "Add account" often silently returns
            // the account already connected in the browser.
            additionalParameters: ["prompt": "select_account", "include_granted_scopes": "true"]
        )

        let authState = try await presentAuthorization(request: request, window: presentingWindow)
        let session = AuthSession(authState: authState)
        guard Self.grantedScopes(of: session).contains(Self.driveReadonlyScope) else {
            throw LoginManagerError.missingDrivePermission
        }

        let fallbackAccount = Self.accountFromIDToken(in: session)
        // Validate and identify the session before touching Keychain. If OAuth
        // fails halfway through, an already-connected copy of this account is
        // left exactly as it was instead of being overwritten and then removed.
        let token = try await accessToken(
            for: session,
            accountID: fallbackAccount.userID,
            persistSession: false
        )
        let account = (try? await Self.fetchProfile(accessToken: token)) ?? fallbackAccount
        guard account.userID != Self.unknownAccountID else {
            throw LoginManagerError.missingAccountIdentity
        }
        try storeSession(session, accountID: account.userID)

        var accounts = loadStoredAccounts()
        Self.upsert(account, in: &accounts)
        saveAccounts(accounts)
        if loadDefaultAccountID() == nil { saveDefaultAccountID(account.userID) }
        return currentSnapshot()
    }

    func removeAccount(userID: String) -> GoogleAccountSnapshot {
        removeSession(accountID: userID)
        var accounts = loadStoredAccounts()
        accounts.removeAll { $0.userID == userID }
        saveAccounts(accounts)

        let defaultID = loadDefaultAccountID()
        if defaultID == userID || !accounts.contains(where: { $0.userID == defaultID }) {
            saveDefaultAccountID(accounts.first?.userID)
        }
        return currentSnapshot()
    }

    func setDefaultAccount(userID: String) -> GoogleAccountSnapshot {
        guard loadStoredAccounts().contains(where: { $0.userID == userID }) else {
            return currentSnapshot()
        }
        saveDefaultAccountID(userID)
        return currentSnapshot()
    }

    // MARK: - Tokens

    func cachedAccessTokens(preferredAccountID: String?) async -> GoogleAccessTokenSet {
        migrateLegacySessionIfPresent()
        let accounts = loadStoredAccounts()
        let accountIDs = orderedAccountIDs(accounts: accounts, preferredAccountID: preferredAccountID)
        var tokens: [GoogleAccessToken] = []

        for accountID in accountIDs {
            guard let session = loadSession(for: accountID), session.authState.isAuthorized,
                  Self.grantedScopes(of: session).contains(Self.driveReadonlyScope),
                  let token = try? await accessToken(for: session, accountID: accountID) else {
                continue
            }
            tokens.append(GoogleAccessToken(accountID: accountID, token: token))
        }

        return GoogleAccessTokenSet(hasAccounts: !accounts.isEmpty, tokens: tokens)
    }

    func validAccessToken(for accountID: String?) async throws -> GoogleAccessToken {
        let available = await cachedAccessTokens(preferredAccountID: accountID)
        guard let token = available.tokens.first else { throw LoginManagerError.notSignedIn }
        return token
    }

    /// Refreshes the access token if needed and persists a rotated refresh token
    /// back into only the Keychain item belonging to this account.
    private func accessToken(
        for session: AuthSession,
        accountID: String,
        persistSession: Bool = true
    ) async throws -> String {
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
        if persistSession { try? storeSession(session, accountID: accountID) }
        return token
    }

    // MARK: - Keychain and migration

    private func keychainStore(for accountID: String) -> KeychainStore {
        KeychainStore(
            itemName: KeychainNamespace.sessionItem(for: accountID),
            keychainAttributes: [.useFileBasedKeychain]
        )
    }

    private func loadSession(for accountID: String) -> AuthSession? {
        if let active = activeSessions[accountID] { return active }
        guard let restored = try? keychainStore(for: accountID).retrieveAuthSession() else { return nil }
        activeSessions[accountID] = restored
        return restored
    }

    private func storeSession(_ session: AuthSession, accountID: String) throws {
        try keychainStore(for: accountID).save(authSession: session)
        activeSessions[accountID] = session
    }

    private func removeSession(accountID: String) {
        activeSessions[accountID] = nil
        try? keychainStore(for: accountID).removeAuthSession()
    }

    /// v6.23 and earlier stored one OAuth session under the base item name and
    /// one profile in UserDefaults. Move it once, only deleting the old item
    /// after the per-account write succeeds. If that write is temporarily
    /// blocked, keep the legacy session active and retry on the next call.
    private func migrateLegacySessionIfPresent() {
        guard let legacySession = try? legacyKeychainStore.retrieveAuthSession(),
              legacySession.authState.isAuthorized else { return }

        let tokenAccount = Self.accountFromIDToken(in: legacySession)
        let legacyProfile = loadLegacyAccount()
        let account: GoogleAccount
        if tokenAccount.userID == Self.unknownAccountID, let legacyProfile {
            account = legacyProfile
        } else {
            account = legacyProfile?.userID == tokenAccount.userID ? legacyProfile! : tokenAccount
        }
        activeSessions[account.userID] = legacySession

        var accounts = loadStoredAccounts()
        Self.upsert(account, in: &accounts)
        saveAccounts(accounts)
        if loadDefaultAccountID() == nil { saveDefaultAccountID(account.userID) }

        do {
            try storeSession(legacySession, accountID: account.userID)
            try legacyKeychainStore.removeAuthSession()
            userDefaults.removeObject(forKey: StorageKey.legacyGoogleAccount)
        } catch {
            // The old item remains untouched and active for this launch.
        }
    }

    // MARK: - AppAuth plumbing

    private static let googleConfiguration = OIDServiceConfiguration(
        authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
    )

    private func presentAuthorization(request: OIDAuthorizationRequest, window: NSWindow) async throws -> OIDAuthState {
        let boxed: UncheckedSendable<OIDAuthState> = try await withCheckedThrowingContinuation { continuation in
            currentAuthorizationFlow = OIDAuthState.authState(
                byPresenting: request,
                presenting: window
            ) { authState, error in
                self.currentAuthorizationFlow = nil
                if let authState {
                    continuation.resume(returning: UncheckedSendable(authState))
                } else {
                    continuation.resume(throwing: error ?? LoginManagerError.notSignedIn)
                }
            }
        }
        return boxed.value
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

    /// AppAuth parses the ID token received from Google's TLS token endpoint.
    /// These claims are display fallback only; Drive authorization still uses
    /// the access token and verified scope above.
    private static func accountFromIDToken(in session: AuthSession) -> GoogleAccount {
        let rawIDToken = session.authState.lastTokenResponse?.idToken
            ?? session.authState.lastAuthorizationResponse.idToken
        let claims = rawIDToken.flatMap { OIDIDToken(idTokenString: $0)?.claims as? [String: Any] }
        let email = claims?["email"] as? String ?? session.userEmail ?? "Google account"
        return GoogleAccount(
            userID: claims?["sub"] as? String ?? session.userID ?? unknownAccountID,
            name: claims?["name"] as? String ?? email,
            email: email,
            profileImageURL: (claims?["picture"] as? String).flatMap(URL.init(string:))
        )
    }

    private static let unknownAccountID = "google-account"

    // MARK: - Metadata

    private func currentSnapshot() -> GoogleAccountSnapshot {
        let accounts = loadStoredAccounts()
        let reconnectIDs = Set(accounts.compactMap { account -> String? in
            guard let session = loadSession(for: account.userID), session.authState.isAuthorized,
                  Self.grantedScopes(of: session).contains(Self.driveReadonlyScope) else {
                return account.userID
            }
            return nil
        })
        return snapshot(accounts: accounts, reconnectIDs: reconnectIDs)
    }

    private func snapshot(accounts: [GoogleAccount], reconnectIDs: Set<String>) -> GoogleAccountSnapshot {
        let storedDefault = loadDefaultAccountID()
        let resolvedDefault = accounts.contains(where: { $0.userID == storedDefault })
            ? storedDefault
            : accounts.first?.userID
        if resolvedDefault != storedDefault { saveDefaultAccountID(resolvedDefault) }
        return GoogleAccountSnapshot(
            accounts: accounts,
            defaultAccountID: resolvedDefault,
            reconnectAccountIDs: reconnectIDs
        )
    }

    private func orderedAccountIDs(accounts: [GoogleAccount], preferredAccountID: String?) -> [String] {
        var result: [String] = []
        let candidates: [String?] = [preferredAccountID, loadDefaultAccountID()]
            + accounts.map { Optional($0.userID) }
        for candidate in candidates {
            guard let candidate, accounts.contains(where: { $0.userID == candidate }),
                  !result.contains(candidate) else { continue }
            result.append(candidate)
        }
        return result
    }

    private static func upsert(_ account: GoogleAccount, in accounts: inout [GoogleAccount]) {
        if let index = accounts.firstIndex(where: { $0.userID == account.userID }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
    }

    private func loadStoredAccounts() -> [GoogleAccount] {
        guard let data = userDefaults.data(forKey: StorageKey.accounts),
              let decoded = try? JSONDecoder().decode([GoogleAccount].self, from: data) else { return [] }
        var seen: Set<String> = []
        return decoded.filter { seen.insert($0.userID).inserted }
    }

    private func saveAccounts(_ accounts: [GoogleAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        userDefaults.set(data, forKey: StorageKey.accounts)
    }

    private func loadLegacyAccount() -> GoogleAccount? {
        guard let data = userDefaults.data(forKey: StorageKey.legacyGoogleAccount) else { return nil }
        return try? JSONDecoder().decode(GoogleAccount.self, from: data)
    }

    private func loadDefaultAccountID() -> String? {
        userDefaults.string(forKey: StorageKey.defaultAccountID)
    }

    private func saveDefaultAccountID(_ accountID: String?) {
        if let accountID { userDefaults.set(accountID, forKey: StorageKey.defaultAccountID) }
        else { userDefaults.removeObject(forKey: StorageKey.defaultAccountID) }
    }

    private var configuredClientID: String? {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty, !clientID.contains("YOUR_") else { return nil }
        return clientID
    }

    private static func redirectURL(clientID: String) -> URL? {
        let reversed = Bundle.main.object(forInfoDictionaryKey: "REVERSED_CLIENT_ID") as? String
            ?? "com.googleusercontent.apps." + clientID.replacingOccurrences(
                of: ".apps.googleusercontent.com",
                with: ""
            )
        return URL(string: "\(reversed):/oauthredirect")
    }
}

enum LoginManagerError: LocalizedError {
    case missingClientID
    case missingPresentingWindow
    case notSignedIn
    case missingAccessToken
    case missingDrivePermission
    case missingAccountIdentity

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
        case .missingDrivePermission:
            "Google Drive permission is required to use this account."
        case .missingAccountIdentity:
            "Google did not return an account identity. Please try connecting again."
        }
    }
}

struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

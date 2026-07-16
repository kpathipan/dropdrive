import AppKit
import Foundation
import GoogleSignIn
import os.log

private let ddAuthLog = Logger(subsystem: "com.dropdrive.DropDrive", category: "auth")

protocol LoginManaging {
    func restoreSavedAccount() async -> GoogleAccount?
    func signIn() async throws -> GoogleAccount
    func signOut()
    func handleCallbackURL(_ url: URL) -> Bool
    func validAccessToken() async throws -> String
    func cachedAccessTokenIfAvailable() async -> String?
}

@MainActor
final class LoginManager: LoginManaging {
    static let shared = LoginManager()

    static let driveReadonlyScope = "https://www.googleapis.com/auth/drive.readonly"

    private enum StorageKey {
        static let googleAccount = "googleAccount"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func restoreSavedAccount() async -> GoogleAccount? {
        if let user = GIDSignIn.sharedInstance.currentUser {
            let account = GoogleAccount(user: user)
            save(account)
            return account
        }

        // Only surface "connected" when a real session actually exists. Returning
        // the UserDefaults-cached account regardless (the old behaviour) let the
        // account chip claim signed-in while every private-file analysis still
        // failed with "needs authentication", because the chip was reading cached
        // display data that nothing kept in sync with the real GID session.
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else {
            userDefaults.removeObject(forKey: StorageKey.googleAccount)
            return nil
        }

        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            let account = GoogleAccount(user: user)
            save(account)
            return account
        } catch {
            return loadStoredAccount()
        }
    }

    func signIn() async throws -> GoogleAccount {
        guard isGoogleSignInConfigured else {
            ddAuthLog.error("signIn: not configured (missing client id)")
            throw LoginManagerError.missingClientID
        }

        guard let presentingWindow = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
            ddAuthLog.error("signIn: no presenting window")
            throw LoginManagerError.missingPresentingWindow
        }

        ddAuthLog.log("signIn: presenting GID sheet on window=\(presentingWindow.title, privacy: .public)")
        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingWindow,
                hint: nil,
                additionalScopes: [Self.driveReadonlyScope]
            )
            ddAuthLog.log("signIn: GID returned user=\(result.user.profile?.email ?? "?", privacy: .public) scopes=\(result.user.grantedScopes?.joined(separator: ",") ?? "none", privacy: .public)")
        } catch {
            ddAuthLog.error("signIn: GID threw: \(String(describing: error), privacy: .public)")
            throw error
        }
        let account = GoogleAccount(user: result.user)
        save(account)
        return account
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        userDefaults.removeObject(forKey: StorageKey.googleAccount)
    }

    func handleCallbackURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// Returns a valid access token only if the user is already signed in with the
    /// required scope, refreshing silently if needed. Never prompts for interaction.
    ///
    /// `GIDSignIn.sharedInstance.currentUser` can still be nil immediately after
    /// launch — populating it from a previous session happens asynchronously
    /// (see `restoreSavedAccount`, called separately from the UI). Analysis
    /// triggered by an incoming deep link can race ahead of that restore and
    /// wrongly conclude "not signed in" even though a valid session exists, so
    /// this attempts the same silent restore itself rather than assuming
    /// something else already did it.
    func cachedAccessTokenIfAvailable() async -> String? {
        var user = GIDSignIn.sharedInstance.currentUser
        ddAuthLog.log("cachedToken: currentUser=\(user != nil, privacy: .public) hasPrevious=\(GIDSignIn.sharedInstance.hasPreviousSignIn(), privacy: .public)")
        if user == nil, GIDSignIn.sharedInstance.hasPreviousSignIn() {
            do {
                user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
                ddAuthLog.log("cachedToken: restorePreviousSignIn succeeded=\(user != nil, privacy: .public)")
            } catch {
                ddAuthLog.error("cachedToken: restorePreviousSignIn failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        guard let user else {
            ddAuthLog.error("cachedToken: no user -> needsAuthentication")
            return nil
        }
        let scopes = user.grantedScopes ?? []
        ddAuthLog.log("cachedToken: grantedScopes=\(scopes.joined(separator: ","), privacy: .public)")
        guard scopes.contains(Self.driveReadonlyScope) else {
            ddAuthLog.error("cachedToken: drive.readonly scope MISSING -> needsAuthentication")
            return nil
        }

        do {
            let token = try await Self.refreshedAccessToken(for: user)
            ddAuthLog.log("cachedToken: token refreshed OK (len=\(token.count, privacy: .public))")
            return token
        } catch {
            ddAuthLog.error("cachedToken: token refresh FAILED: \(error.localizedDescription, privacy: .public) -> needsAuthentication")
            return nil
        }
    }

    func validAccessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw LoginManagerError.notSignedIn
        }

        let authorizedUser: GIDGoogleUser
        if user.grantedScopes?.contains(Self.driveReadonlyScope) == true {
            authorizedUser = user
        } else {
            guard let presentingWindow = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
                throw LoginManagerError.missingPresentingWindow
            }

            let result = try await user.addScopes([Self.driveReadonlyScope], presenting: presentingWindow)
            authorizedUser = result.user
        }

        return try await Self.refreshedAccessToken(for: authorizedUser)
    }

    private static func refreshedAccessToken(for user: GIDGoogleUser) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { refreshedUser, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let token = refreshedUser?.accessToken.tokenString else {
                    continuation.resume(throwing: LoginManagerError.missingAccessToken)
                    return
                }

                continuation.resume(returning: token)
            }
        }
    }

    private var isGoogleSignInConfigured: Bool {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            return false
        }

        return !clientID.isEmpty && !clientID.contains("YOUR_")
    }

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

private extension GoogleAccount {
    init(user: GIDGoogleUser) {
        let profile = user.profile

        self.init(
            userID: user.userID ?? profile?.email ?? UUID().uuidString,
            name: profile?.name ?? "Google User",
            email: profile?.email ?? "No email available",
            profileImageURL: profile?.imageURL(withDimension: 128)
        )
    }
}

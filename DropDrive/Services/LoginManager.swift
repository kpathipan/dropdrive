import AppKit
import Foundation
import GoogleSignIn

protocol LoginManaging {
    func restoreSavedAccount() async -> GoogleAccount?
    func signIn() async throws -> GoogleAccount
    func signOut()
    func handleCallbackURL(_ url: URL) -> Bool
    func validAccessToken() async throws -> String
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

        let storedAccount = loadStoredAccount()

        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else {
            return storedAccount
        }

        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            let account = GoogleAccount(user: user)
            save(account)
            return account
        } catch {
            return storedAccount
        }
    }

    func signIn() async throws -> GoogleAccount {
        guard isGoogleSignInConfigured else {
            throw LoginManagerError.missingClientID
        }

        guard let presentingWindow = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
            throw LoginManagerError.missingPresentingWindow
        }

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingWindow,
            hint: nil,
            additionalScopes: [Self.driveReadonlyScope]
        )
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

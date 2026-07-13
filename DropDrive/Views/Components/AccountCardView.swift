import SwiftUI

struct AccountCardView: View {
    let account: GoogleAccount?
    let isSigningIn: Bool
    let isLocked: Bool
    let onSignIn: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        Group {
            if let account {
                connectedCard(account)
            } else {
                signInButton
            }
        }
        .animation(.easeInOut(duration: 0.2), value: account)
    }

    private func connectedCard(_ account: GoogleAccount) -> some View {
        HStack(spacing: 14) {
            avatar(for: account)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text(account.email)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button(action: onSignOut) {
                Text("Sign Out")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(isLocked)
        }
        .padding(14)
        .cardBackground()
    }

    private func avatar(for account: GoogleAccount) -> some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: account.profileImageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    monogram(for: account)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            Circle()
                .fill(.green)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(.background, lineWidth: 2))
        }
    }

    private func monogram(for account: GoogleAccount) -> some View {
        Circle()
            .fill(Color.accentColor.gradient)
            .overlay {
                Text(account.name.prefix(1).uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    private var signInButton: some View {
        Button(action: onSignIn) {
            HStack(spacing: 8) {
                if isSigningIn {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
                Text(isSigningIn ? "Opening Google Sign-In…" : "Connect Google Drive")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isSigningIn)
    }
}

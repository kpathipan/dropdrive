import SwiftUI

struct ConnectionToolbarControl: View {
    let account: GoogleAccount?
    let isSigningIn: Bool
    let isLocked: Bool
    let onSignIn: () -> Void
    let onSignOut: () -> Void

    @State private var showConnectSheet = false
    @State private var showAccountPopover = false

    var body: some View {
        Group {
            if let account {
                Button {
                    showAccountPopover = true
                } label: {
                    HStack(spacing: 5) {
                        AvatarView(account: account, size: 20)

                        Text(account.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(-1)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 170, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
                .disabled(isLocked)
                .popover(isPresented: $showAccountPopover, arrowEdge: .bottom) {
                    AccountPopoverContent(account: account, onDisconnect: {
                        showAccountPopover = false
                        onSignOut()
                    })
                }
            } else {
                Button {
                    showConnectSheet = true
                } label: {
                    Label("Connect", systemImage: "link")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(isSigningIn)
                .sheet(isPresented: $showConnectSheet) {
                    ConnectSheetContent(
                        isSigningIn: isSigningIn,
                        onContinue: {
                            onSignIn()
                            showConnectSheet = false
                        },
                        onCancel: { showConnectSheet = false }
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: account)
    }
}

private struct AvatarView: View {
    let account: GoogleAccount
    var size: CGFloat = 20

    var body: some View {
        AsyncImage(url: account.profileImageURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Circle()
                    .fill(Color.accentColor.gradient)
                    .overlay {
                        Text(account.name.prefix(1).uppercased())
                            .font(.system(size: size * 0.45, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct ConnectSheetContent: View {
    let isSigningIn: Bool
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text("Connect Google Drive")
                    .font(.system(size: 15, weight: .semibold))

                Text("Connect your Google Drive account to access private files and folders.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }

            HStack(spacing: 10) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Button("Continue with Google", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 340)
    }
}

private struct AccountPopoverContent: View {
    let account: GoogleAccount
    let onDisconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    AvatarView(account: account, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Connected to Google Drive")
                            .font(.system(size: 12, weight: .semibold))
                        Text(account.email)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Divider()

            Button {
                NSWorkspace.shared.open(URL(string: "https://myaccount.google.com/permissions")!)
            } label: {
                Text("Manage Connection")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDisconnect) {
                Text("Disconnect")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(14)
        .frame(width: 240)
    }
}

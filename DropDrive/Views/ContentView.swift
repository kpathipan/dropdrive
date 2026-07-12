import SwiftUI

struct ContentView: View {
    @State private var viewModel = DropDriveViewModel()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.06, blue: 0.08), Color(red: 0.08, green: 0.10, blue: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                header
                accountSection
                form
                footer
            }
            .padding(32)
            .frame(width: 620, height: 520)
        }
        .preferredColorScheme(.dark)
        .task {
            viewModel.restoreLogin()
        }
        .onOpenURL { url in
            viewModel.handleCallbackURL(url)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DropDrive")
                .font(.system(size: 36, weight: .semibold, design: .rounded))

            Text("Download Google Drive folders to a local destination.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var accountSection: some View {
        Group {
            if let account = viewModel.googleAccount {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill.badge.checkmark")
                        .font(.system(size: 28))
                        .foregroundStyle(.green, .white.opacity(0.85))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Connected as:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(account.name)
                            .font(.headline)
                            .lineLimit(1)

                        Text(account.email)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 16)

                    Button(action: viewModel.signOut) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(viewModel.isWorking)
                }
                .padding(14)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
            } else {
                Button(action: viewModel.signInWithGoogle) {
                    Label(viewModel.isWorking ? "Opening Google..." : "Connect Google Drive", systemImage: "g.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(isProminent: false))
                .disabled(viewModel.isWorking)
            }
        }
    }

    private var form: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Google Drive Link")
                    .font(.headline)

                TextField("https://drive.google.com/drive/folders/...", text: $viewModel.driveLink)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Destination")
                    .font(.headline)

                HStack(spacing: 12) {
                    Text(viewModel.destinationDisplayName)
                        .foregroundStyle(viewModel.selectedDestinationURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 16)

                    Button(action: viewModel.chooseDestinationFolder) {
                        Label("Choose", systemImage: "folder")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(viewModel.isWorking)
                }
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: viewModel.download) {
                Label("Download", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(isProminent: true))
            .disabled(!viewModel.canDownload)

            Text(viewModel.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(isProminent ? 0.18 : 0.12), lineWidth: 1)
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isProminent {
            return isPressed ? Color.accentColor.opacity(0.75) : Color.accentColor
        }

        return isPressed ? .white.opacity(0.10) : .white.opacity(0.07)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(configuration.isPressed ? 0.14 : 0.09), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    ContentView()
}

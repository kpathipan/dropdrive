import SwiftUI

struct ContentView: View {
    @State private var viewModel = DropDriveViewModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                header

                AccountCardView(
                    account: viewModel.googleAccount,
                    isSigningIn: viewModel.isSigningIn,
                    isLocked: viewModel.isFormLocked,
                    onSignIn: viewModel.signInWithGoogle,
                    onSignOut: viewModel.signOut
                )

                DownloadFormView(
                    driveLink: $viewModel.driveLink,
                    destinationURL: viewModel.selectedDestinationURL,
                    isLocked: viewModel.isFormLocked,
                    onChooseDestination: viewModel.chooseDestinationFolder
                )

                resultArea

                if case .idle = viewModel.downloadPhase {
                    Button(action: viewModel.download) {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!viewModel.canDownload)
                }

                if !viewModel.statusMessage.isEmpty, viewModel.downloadPhase == .idle {
                    Text(viewModel.statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 40)

            Divider()

            StatusBarView(
                statusText: viewModel.footerStatusText,
                isConnected: viewModel.isGoogleSignedIn
            )
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background(.background)
        .animation(.easeInOut(duration: 0.25), value: viewModel.downloadPhase)
        .task {
            viewModel.restoreLogin()
        }
        .onOpenURL { url in
            viewModel.handleCallbackURL(url)
        }
    }

    @ViewBuilder
    private var resultArea: some View {
        switch viewModel.downloadPhase {
        case .idle:
            EmptyView()
        case .downloading:
            if let progress = viewModel.downloadProgress {
                DownloadProgressView(progress: progress, onCancel: viewModel.cancelDownload)
            }
        case .success(let folderURL, let fileCount):
            DownloadSuccessView(
                folderURL: folderURL,
                fileCount: fileCount,
                onOpenInFinder: { NSWorkspace.shared.activateFileViewerSelecting([folderURL]) },
                onDone: viewModel.dismissDownloadResult
            )
        case .failed(let message):
            DownloadErrorView(
                message: message,
                onRetry: viewModel.retryDownload,
                onDismiss: viewModel.dismissDownloadResult
            )
        case .cancelled:
            DownloadCancelledView(onDismiss: viewModel.dismissDownloadResult)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DropDrive")
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            Text("Download Google Drive folders effortlessly.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}

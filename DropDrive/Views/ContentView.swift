import SwiftUI

struct ContentView: View {
    @State private var viewModel = DropDriveViewModel()
    @State private var recentDownloads: [DownloadHistoryItem] = []

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    header

                    DownloadFormView(
                        driveLink: $viewModel.driveLink,
                        destinationURL: viewModel.selectedDestinationURL,
                        isLocked: viewModel.isFormLocked,
                        onChooseDestination: viewModel.chooseDestinationFolder
                    )
                    .frame(maxWidth: 360)

                    if case .idle = viewModel.downloadPhase {
                        analysisArea
                            .frame(maxWidth: 360)
                    }

                    resultArea
                        .frame(maxWidth: 360)

                    if case .idle = viewModel.downloadPhase, viewModel.linkAnalysisState == .idle, recentDownloads.isEmpty {
                        EmptyStateView()
                            .frame(maxWidth: 360)
                    } else if !recentDownloads.isEmpty {
                        RecentDownloadsView(items: recentDownloads)
                            .frame(maxWidth: 360)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }

            Divider()

            StatusBarView(statusText: statusBarText)
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 480, idealHeight: 600)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ConnectionToolbarControl(
                    account: viewModel.googleAccount,
                    isSigningIn: viewModel.isSigningIn,
                    isLocked: viewModel.isFormLocked,
                    onSignIn: viewModel.signInWithGoogle,
                    onSignOut: viewModel.signOut
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.downloadPhase)
        .animation(.easeInOut(duration: 0.2), value: viewModel.linkAnalysisState)
        .task {
            viewModel.restoreLogin()
        }
        .onOpenURL { url in
            viewModel.handleCallbackURL(url)
        }
        .onChange(of: viewModel.downloadPhase) { _, newPhase in
            recordHistoryIfNeeded(for: newPhase)
        }
    }

    private func recordHistoryIfNeeded(for phase: DownloadPhase) {
        switch phase {
        case .success(let folderURL, _):
            recentDownloads.insert(DownloadHistoryItem(name: folderURL.lastPathComponent, date: .now, status: .completed), at: 0)
        case .failed:
            let name = GoogleDriveLinkParser.itemID(from: viewModel.driveLink) != nil ? "Google Drive download" : "Download"
            recentDownloads.insert(DownloadHistoryItem(name: name, date: .now, status: .failed), at: 0)
        case .cancelled:
            recentDownloads.insert(DownloadHistoryItem(name: "Google Drive download", date: .now, status: .cancelled), at: 0)
        default:
            break
        }
    }

    private var statusBarText: String {
        switch viewModel.downloadPhase {
        case .idle: "Ready"
        case .downloading: "Downloading"
        case .success: "Completed"
        case .failed: "Error"
        case .cancelled: "Ready"
        }
    }

    @ViewBuilder
    private var resultArea: some View {
        switch viewModel.downloadPhase {
        case .idle:
            EmptyView()
        case .downloading:
            if let progress = viewModel.downloadProgress {
                DownloadPanelView(progress: progress, onCancel: viewModel.cancelDownload)
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

    @ViewBuilder
    private var analysisArea: some View {
        switch viewModel.linkAnalysisState {
        case .idle:
            EmptyView()
        case .analyzing:
            LinkAnalyzingView()
        case .needsConnection:
            LinkNeedsConnectionView(isSigningIn: viewModel.isSigningIn, onConnect: viewModel.signInWithGoogle)
        case .ready(let analysis):
            LinkAnalysisResultView(
                analysis: analysis,
                canDownload: viewModel.canDownload,
                onDownload: viewModel.download,
                onCancel: viewModel.cancelAnalysis
            )
        case .failed(let message):
            LinkAnalysisErrorView(message: message, onRetry: viewModel.retryAnalysis)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("DropDrive")
                .font(.system(size: 28, weight: .semibold, design: .rounded))

            Text("Download Google Drive files and folders directly to your Mac.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 264)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

#Preview {
    ContentView()
}

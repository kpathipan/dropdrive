import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = DropDriveViewModel()
    @State private var historyStore = DownloadHistoryStore.shared
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    header

                    DownloadFormView(
                        driveLink: $viewModel.driveLink,
                        destinationURL: viewModel.selectedDestinationURL,
                        isLocked: viewModel.isFormLocked,
                        onChooseDestination: viewModel.chooseDestinationFolder,
                        onSubmit: viewModel.handleSubmit,
                        onEscape: viewModel.cancelAnalysis
                    )
                    .frame(maxWidth: 360)

                    if case .idle = viewModel.downloadPhase {
                        analysisArea
                            .frame(maxWidth: 360)
                    }

                    resultArea
                        .frame(maxWidth: 360)

                    if case .idle = viewModel.downloadPhase, viewModel.linkAnalysisState == .idle, historyStore.items.isEmpty {
                        EmptyStateView()
                            .frame(maxWidth: 360)
                    } else if !historyStore.items.isEmpty {
                        RecentDownloadsView(
                            items: historyStore.items,
                            onRevealInFinder: { item in
                                guard let url = item.itemURL else { return }
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            },
                            onCopyLink: { item in
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(item.driveLink, forType: .string)
                            },
                            onClearHistory: { historyStore.clear() }
                        )
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
        .background(WindowAccessor(autosaveName: "DropDriveMainWindow"))
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.url, .plainText], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
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
    }

    /// Accepts a dragged Drive link as either a file-style URL promise or plain text.
    /// If the dropped content doesn't parse as a Drive link, the field is left untouched.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !viewModel.isFormLocked else { return false }

        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) else {
            return false
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                guard let url, GoogleDriveLinkParser.itemID(from: url.absoluteString) != nil else { return }
                Task { @MainActor in viewModel.driveLink = url.absoluteString }
            }
            return true
        }

        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
            let text = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
            guard let text, GoogleDriveLinkParser.itemID(from: text) != nil else { return }
            Task { @MainActor in viewModel.driveLink = text }
        }
        return true
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
        case .success(let itemURL, let isFolder, let fileCount):
            DownloadSuccessView(
                itemURL: itemURL,
                isFolder: isFolder,
                fileCount: fileCount,
                onOpenInFinder: { NSWorkspace.shared.activateFileViewerSelecting([itemURL]) },
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
        case .invalidLink:
            LinkInvalidView()
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

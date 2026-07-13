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
    /// Tries the URL representation first, then falls back to plain text if the URL
    /// doesn't parse as a Drive link (a provider can offer both, and the URL one isn't
    /// always the useful one — e.g. dragging selected text from a page). If neither
    /// yields a valid link, the field is left untouched.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !viewModel.isFormLocked else { return false }

        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) else {
            return false
        }

        Task { @MainActor in
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let candidate = await Self.loadedString(from: provider, typeIdentifier: UTType.url.identifier),
               GoogleDriveLinkParser.itemID(from: candidate) != nil {
                viewModel.driveLink = candidate
                return
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let candidate = await Self.loadedString(from: provider, typeIdentifier: UTType.plainText.identifier),
               GoogleDriveLinkParser.itemID(from: candidate) != nil {
                viewModel.driveLink = candidate
            }
        }
        return true
    }

    private static func loadedString(from provider: NSItemProvider, typeIdentifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier) { item, _ in
                switch item {
                case let url as URL:
                    continuation.resume(returning: url.absoluteString)
                case let string as String:
                    continuation.resume(returning: string)
                case let data as Data:
                    if typeIdentifier == UTType.url.identifier, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        continuation.resume(returning: url.absoluteString)
                    } else {
                        continuation.resume(returning: String(data: data, encoding: .utf8))
                    }
                default:
                    continuation.resume(returning: nil)
                }
            }
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

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = DropDriveViewModel()
    @State private var historyStore = DownloadHistoryStore.shared
    @State private var isDropTargeted = false
    @State private var historySearchText = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 22) {
                        header

                        DownloadFormView(
                            driveLink: $viewModel.driveLink,
                            destinationURL: viewModel.selectedDestinationURL,
                            isLocked: viewModel.isSigningIn,
                            onChooseDestination: viewModel.chooseDestinationFolder,
                            onSubmit: viewModel.handleSubmit,
                            onEscape: viewModel.cancelAnalysis
                        )
                        .frame(maxWidth: 360)

                        analysisArea
                            .frame(maxWidth: 360)

                        if !viewModel.queue.isEmpty {
                            QueueView(
                                queue: viewModel.queue,
                                summary: viewModel.queueSummary,
                                canStartQueue: viewModel.canStartQueue,
                                isLargeDownload: viewModel.isLargeDownload,
                                showLargeDownloadWarning: viewModel.showLargeDownloadWarning,
                                activeProgress: viewModel.activeProgress,
                                highlightedItemID: viewModel.highlightedQueueItemID,
                                canPauseQueue: viewModel.canPauseQueue,
                                canResumeQueue: viewModel.canResumeQueue,
                                onStartQueue: viewModel.startQueueDownloads,
                                onConfirmLargeDownload: viewModel.confirmLargeDownloadAndStart,
                                onCancelLargeDownload: viewModel.cancelLargeDownloadWarning,
                                onRemove: viewModel.removeQueueItem,
                                onRetry: viewModel.retryQueueItem,
                                onCancelActive: viewModel.cancelActiveDownload,
                                onRevealInFinder: { item in
                                    guard let url = item.resultURL else { return }
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                },
                                onClearCompleted: viewModel.clearCompletedQueueItems,
                                onPauseQueue: viewModel.pauseQueue,
                                onResumeQueue: viewModel.resumeQueue,
                                onReorder: viewModel.moveQueueItem
                            )
                            .frame(maxWidth: 360)
                        }

                        if viewModel.linkAnalysisState == .idle, viewModel.queue.isEmpty, historyStore.items.isEmpty {
                            EmptyStateView()
                                .frame(maxWidth: 360)
                        } else if !historyStore.items.isEmpty {
                            RecentDownloadsView(
                                items: historyStore.items,
                                searchText: $historySearchText,
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
                .onChange(of: viewModel.activeQueueItemID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
                .onChange(of: viewModel.queue.count) { _, _ in
                    guard let lastID = viewModel.queue.last?.id else { return }
                    withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                }
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
        .onDrop(of: [.url, .fileURL, .plainText], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ConnectionToolbarControl(
                    account: viewModel.googleAccount,
                    isSigningIn: viewModel.isSigningIn,
                    isLocked: viewModel.isQueueProcessing,
                    onSignIn: viewModel.signInWithGoogle,
                    onSignOut: viewModel.signOut
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.linkAnalysisState)
        .animation(.easeInOut(duration: 0.2), value: viewModel.queue)
        .task {
            viewModel.restoreLogin()
        }
        .onOpenURL { url in
            viewModel.handleIncomingURL(url)
        }
        .alert("Restore previous queue?", isPresented: $viewModel.showRestorePrompt) {
            Button("Discard", role: .destructive) { viewModel.discardSavedQueue() }
            Button("Restore") { viewModel.restoreSavedQueue() }
        } message: {
            Text(restoreMessage)
        }
    }

    private var restoreMessage: String {
        let count = viewModel.pendingRestoreQueue?.count ?? 0
        return "You have \(count) item\(count == 1 ? "" : "s") from your last session."
    }

    /// Accepts a dragged Drive link from a browser tab/address bar (`.url`), a dragged
    /// `.webloc`/URL file from Finder (`.fileURL`), or dragged selected text (`.plainText`).
    /// Tries each representation in turn and stops at the first one that parses as a
    /// Drive link — a provider can offer several, and the first one isn't always the
    /// useful one (e.g. dragging selected text from a page). If none yield a valid
    /// link, the field is left untouched.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !viewModel.isSigningIn else { return false }

        let candidateTypes = [UTType.url, UTType.fileURL, UTType.plainText]
        guard let provider = providers.first(where: { provider in
            candidateTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        }) else {
            return false
        }

        Task { @MainActor in
            for type in candidateTypes where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                if let candidate = await Self.loadedString(from: provider, typeIdentifier: type.identifier),
                   GoogleDriveLinkParser.itemID(from: candidate) != nil {
                    viewModel.driveLink = candidate
                    return
                }
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
        if viewModel.isQueueProcessing { return "Downloading" }
        if viewModel.queue.contains(where: { $0.status == .failed }) { return "Error" }
        return "Ready"
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
        case .failed(let message):
            LinkAnalysisErrorView(message: message, onRetry: viewModel.retryAnalysis)
        case .duplicateActive:
            LinkDuplicateActiveView()
        case .duplicateCompleted(let analysis):
            DuplicateCompletedPromptView(
                analysis: analysis,
                onDownloadAgain: viewModel.confirmDuplicateRedownload,
                onCancel: viewModel.cancelAnalysis
            )
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

import SwiftUI
import UniformTypeIdentifiers

/// The whole app UI, shown as the menu bar extra's window. A narrow icon rail
/// on the left switches the detail pane between the download queue, recent
/// downloads, statistics, and preferences — there is no separate main window.
struct MenuBarView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case queue
        case recent
        case stats
        case prefs

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .queue: "arrow.down.circle"
            case .recent: "clock.arrow.circlepath"
            case .stats: "chart.bar"
            case .prefs: "gearshape"
            }
        }

        var title: String {
            switch self {
            case .queue: "Queue"
            case .recent: "Recent"
            case .stats: "Statistics"
            case .prefs: "Preferences"
            }
        }
    }

    @State private var viewModel = DropDriveViewModel.shared
    @State private var historyStore = DownloadHistoryStore.shared
    @State private var selectedPane: Pane = .queue
    @State private var isDropTargeted = false
    @State private var historySearchText = ""

    var body: some View {
        HStack(spacing: 0) {
            rail

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 380, height: 420)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.url, .fileURL, .plainText], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .task {
            viewModel.restoreLogin()
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

    // MARK: - Rail

    private var rail: some View {
        VStack(spacing: 6) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
                .padding(.bottom, 6)

            ForEach(Pane.allCases) { pane in
                railButton(pane)
            }

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Quit DropDrive")
            .accessibilityLabel("Quit DropDrive")
        }
        .padding(.vertical, 10)
        .frame(width: 42)
        .background(.quaternary.opacity(0.35))
    }

    private func railButton(_ pane: Pane) -> some View {
        Button {
            selectedPane = pane
        } label: {
            Image(systemName: pane.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selectedPane == pane ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selectedPane == pane ? Color.accentColor.opacity(0.14) : .clear)
                )
                .overlay(alignment: .topTrailing) {
                    if pane == .queue, activeCount > 0 {
                        Text("\(activeCount)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor))
                            .offset(x: 4, y: -2)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(pane.title)
        .accessibilityLabel(pane.title)
        .accessibilityAddTraits(selectedPane == pane ? .isSelected : [])
    }

    private var activeCount: Int {
        viewModel.queue.filter { $0.status == .ready || $0.status == .downloading || $0.status == .paused }.count
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedPane {
        case .queue:
            queuePane
        case .recent:
            recentPane
        case .stats:
            statsPane
        case .prefs:
            PreferencesView()
        }
    }

    private var paneHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Text("Drop").foregroundStyle(.primary)
                Text("Drive").foregroundStyle(Color(red: 0.145, green: 0.388, blue: 0.922))
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .accessibilityElement()
            .accessibilityLabel("DropDrive")

            Spacer()

            ConnectionToolbarControl(
                account: viewModel.googleAccount,
                isSigningIn: viewModel.isSigningIn,
                isLocked: viewModel.isQueueProcessing,
                onSignIn: viewModel.signInWithGoogle,
                onSignOut: viewModel.signOut
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var queuePane: some View {
        VStack(spacing: 0) {
            paneHeader

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        DownloadFormView(
                            driveLink: $viewModel.driveLink,
                            destinationURL: viewModel.selectedDestinationURL,
                            isLocked: viewModel.isSigningIn,
                            onChooseDestination: viewModel.chooseDestinationFolder,
                            onSubmit: viewModel.handleSubmit,
                            onEscape: viewModel.cancelAnalysis
                        )

                        analysisArea

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
                        } else if viewModel.linkAnalysisState == .idle {
                            emptyQueueHint
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
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
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.linkAnalysisState)
        .animation(.easeInOut(duration: 0.2), value: viewModel.queue)
    }

    private var emptyQueueHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Paste or drop a Google Drive link to start.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
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

    private var recentPane: some View {
        VStack(spacing: 0) {
            paneHeader

            ScrollView {
                VStack(spacing: 16) {
                    if historyStore.items.isEmpty {
                        EmptyStateView()
                            .padding(.top, 24)
                    } else {
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
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    private var statsPane: some View {
        Form {
            StatisticsSection()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Drop handling

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
                    selectedPane = .queue
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
}

// MARK: - Preview

#Preview {
    MenuBarView()
}

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
    @State private var showQuitConfirm = false
    /// Live height of the active pane's content, reported by ContentHeightKey.
    /// The window hugs this (capped), so it grows and shrinks with the queue.
    @State private var measuredHeight: CGFloat = 110

    private static let springMotion = Animation.spring(response: 0.38, dampingFraction: 0.86)
    private static let paneHeaderAllowance: CGFloat = 36
    private static let maxWindowHeight: CGFloat = 480
    /// The rail's natural height (logo + four tabs + avatar + power, plus
    /// spacing and padding). Any shorter and the HStack centers the rail,
    /// clipping the logo off the top and the power button off the bottom.
    private static let minWindowHeight: CGFloat = 258

    private var windowHeight: CGFloat {
        let raw: CGFloat
        switch selectedPane {
        case .queue, .recent:
            raw = measuredHeight + Self.paneHeaderAllowance
        case .stats:
            raw = 230
        case .prefs:
            raw = 330
        }
        return min(max(raw, Self.minWindowHeight), Self.maxWindowHeight)
    }

    var body: some View {
        HStack(spacing: 0) {
            rail

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 340, height: windowHeight)
        .background(DDTheme.canvas)
        .tint(DDTheme.accent)
        // The popover is designed light-only (white cards on a light canvas);
        // letting it invert in system dark mode breaks every fixed color above.
        .colorScheme(.light)
        .animation(Self.springMotion, value: windowHeight)
        .onPreferenceChange(ContentHeightKey.self) { height in
            guard height > 0 else { return }
            withAnimation(Self.springMotion) { measuredHeight = height }
        }
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
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
                .padding(.bottom, 6)

            ForEach(Pane.allCases) { pane in
                railButton(pane)
            }

            Spacer()

            RailAccountButton(
                account: viewModel.googleAccount,
                isSigningIn: viewModel.isSigningIn,
                isLocked: viewModel.isQueueProcessing,
                onSignIn: viewModel.signInWithGoogle,
                onSignOut: viewModel.signOut
            )

            Button {
                if viewModel.isQueueProcessing {
                    showQuitConfirm = true
                } else {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Quit DropDrive")
            .accessibilityLabel("Quit DropDrive")
            .confirmationDialog(
                "A download is in progress. Quit anyway?",
                isPresented: $showQuitConfirm
            ) {
                Button("Quit and stop downloading", role: .destructive) { NSApp.terminate(nil) }
                Button("Keep downloading", role: .cancel) {}
            }
        }
        .padding(.vertical, 10)
        .frame(width: 42)
        .background(DDTheme.rail)
    }

    private func railButton(_ pane: Pane) -> some View {
        Button {
            withAnimation(Self.springMotion) { selectedPane = pane }
        } label: {
            Image(systemName: pane.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selectedPane == pane ? DDTheme.accent : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selectedPane == pane ? DDTheme.accentSoft : .clear)
                )
                .overlay(alignment: .topTrailing) {
                    if pane == .queue, activeCount > 0 {
                        Text("\(activeCount)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(DDTheme.accent))
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
            queuePane.transition(.opacity)
        case .recent:
            recentPane.transition(.opacity)
        case .stats:
            statsPane.transition(.opacity)
        case .prefs:
            PreferencesView().transition(.opacity)
        }
    }

    private var paneHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Text("Drop").foregroundStyle(.primary)
                Text("Drive").foregroundStyle(DDTheme.accent)
            }
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .accessibilityElement()
            .accessibilityLabel("DropDrive")

            Spacer()

            Text(headerStatus)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
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
                            .transition(.opacity.combined(with: .move(edge: .top)))

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
                                onOpen: { item in
                                    guard let url = item.resultURL else { return }
                                    NSWorkspace.shared.open(url)
                                },
                                onClearCompleted: viewModel.clearCompletedQueueItems,
                                onPauseQueue: viewModel.pauseQueue,
                                onResumeQueue: viewModel.resumeQueue,
                                onReorder: viewModel.moveQueueItem
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        } else if viewModel.linkAnalysisState == .idle {
                            if recentCompleted.isEmpty {
                                emptyQueueHint.transition(.opacity)
                            } else {
                                recentPreview.transition(.opacity)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                        }
                    )
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
        .animation(Self.springMotion, value: viewModel.linkAnalysisState)
        .animation(Self.springMotion, value: viewModel.queue)
    }

    private var headerStatus: String {
        if viewModel.isQueueProcessing { return "Downloading…" }
        let cal = Calendar.current
        let today = historyStore.items.filter { $0.status == .completed && cal.isDateInToday($0.date) }.count
        if today > 0 { return "\(today) today" }
        return "Ready"
    }

    private var recentCompleted: [DownloadHistoryItem] {
        historyStore.items.filter { item in
            guard item.status == .completed, let url = item.itemURL else { return false }
            // A row whose file was deleted or moved would have a dead Open
            // button — leave it to the full Recent pane instead.
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    /// Fills the empty-queue space with something useful: the last few finished
    /// downloads, openable in place, with a jump to the full Recent pane.
    private var recentPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)

                Spacer()

                Button("All downloads") {
                    withAnimation(Self.springMotion) { selectedPane = .recent }
                }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(DDTheme.accent)
                    .accessibilityLabel("Show all downloads")
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(Array(recentCompleted.prefix(3).enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().padding(.leading, 32)
                    }
                    recentPreviewRow(item)
                }
            }
            .cardBackground()
        }
    }

    private func recentPreviewRow(_ item: DownloadHistoryItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)

            Text(item.name)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button("Open") {
                guard let url = item.itemURL else { return }
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(DDTheme.accent)
            .accessibilityLabel("Open \(item.name)")

            Button {
                guard let url = item.itemURL else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Reveal in Finder")
            .accessibilityLabel("Reveal \(item.name) in Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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
        .padding(.vertical, 14)
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
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
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

// MARK: - Content height measurement

/// Reports the active pane's natural content height so the window can hug it.
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Rail account button

/// The "P" avatar at the bottom of the rail — tap for account details and
/// disconnect when signed in, or a connect prompt when not.
private struct RailAccountButton: View {
    let account: GoogleAccount?
    let isSigningIn: Bool
    let isLocked: Bool
    let onSignIn: () -> Void
    let onSignOut: () -> Void

    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover = true
        } label: {
            avatar
        }
        .buttonStyle(.plain)
        .disabled(isSigningIn)
        .help(account?.email ?? "Connect Google Drive")
        .accessibilityLabel(account.map { "Account: \($0.name)" } ?? "Connect Google Drive")
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            popoverContent
                .colorScheme(.light)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let account {
            AsyncImage(url: account.profileImageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    initialCircle(String(account.name.prefix(1)).uppercased())
                }
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
    }

    private func initialCircle(_ text: String) -> some View {
        Circle()
            .fill(DDTheme.accent)
            .overlay {
                Text(text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    @ViewBuilder
    private var popoverContent: some View {
        if let account {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    avatar
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.name)
                            .font(.system(size: 12, weight: .semibold))
                        Text(account.email)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
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

                Button {
                    showPopover = false
                    onSignOut()
                } label: {
                    Text("Disconnect")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .disabled(isLocked)
            }
            .padding(14)
            .frame(width: 230)
        } else {
            VStack(spacing: 10) {
                Text("Connect your Google account to download private files and folders.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Continue with Google") {
                    showPopover = false
                    onSignIn()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
            .frame(width: 230)
        }
    }
}

// MARK: - Preview

#Preview {
    MenuBarView()
}

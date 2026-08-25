import SwiftUI

/// The whole app UI, shown as the menu bar extra's window. A narrow icon rail
/// on the left switches the detail pane between the download queue, recent
/// downloads, and statistics. Longer-lived preferences open in their own
/// settings window so the popover stays a fast-action surface.
struct MenuBarView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case queue
        case recent
        case stats

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .queue: "arrow.down.circle"
            case .recent: "clock.arrow.circlepath"
            case .stats: "chart.bar"
            }
        }

        var title: String {
            switch self {
            case .queue: tr("Queue", "คิวดาวน์โหลด")
            case .recent: tr("Recent", "ล่าสุด")
            case .stats: tr("Statistics", "สถิติ")
            }
        }
    }

    @State private var viewModel = DropDriveViewModel.shared
    @State private var historyStore = DownloadHistoryStore.shared
    @State private var selectedPane: Pane = .queue
    @State private var historySearchText = ""
    /// Live height of the active pane's content, reported by ContentHeightKey.
    /// The window hugs this (capped), so it grows and shrinks with the queue.
    @State private var measuredHeight: CGFloat = 110
    /// First-run walkthrough: shown once in place of the whole window, mostly to
    /// tell friends the app lives in the menu bar and has no Dock icon.
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var theme = AppTheme.shared
    @State private var statusCache = FileStatusCache.shared

    private static let springMotion = Animation.spring(response: 0.38, dampingFraction: 0.86)
    /// Fixed chrome above and below the scrolling content: the top logo bar plus
    /// its divider, and the bottom tab bar plus its divider.
    private static let chromeAllowance: CGFloat = 43 + 43
    private static let maxWindowHeight: CGFloat = 560
    private static let minWindowHeight: CGFloat = 160

    private var windowHeight: CGFloat {
        let raw: CGFloat
        switch selectedPane {
        case .queue, .recent:
            raw = measuredHeight + Self.chromeAllowance
        case .stats:
            // The empty-state insight card needs a little more vertical room
            // than the metric row; keeping it visible avoids a mystery card
            // that looks clipped in the compact menu-bar window.
            raw = 390
        }
        return min(max(raw, Self.minWindowHeight), Self.maxWindowHeight)
    }

    var body: some View {
        Group {
            if hasSeenWelcome {
                VStack(spacing: 0) {
                    topBar

                    Divider()

                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    Divider()

                    bottomTabBar
                }
            } else {
                welcomeView
            }
        }
        .frame(width: 400, height: hasSeenWelcome ? windowHeight : 360)
        .font(.dd(13))
        // Frosted, not painted. Every menu bar panel macOS ships — Control
        // Centre, Wi-Fi, Sound — sits on a translucent material, and a flat
        // opaque fill is most of why this window read as pasted onto the screen
        // rather than floating above it. The canvas tint stays on top at low
        // opacity so the palette still holds in both themes; the material alone
        // would take its colour from whatever happens to be behind the window.
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(DDTheme.canvas.opacity(0.72))
        }
        .tint(DDTheme.accent)
        // Pin the scheme to the in-app theme (system/light/dark) rather than the
        // window's inherited appearance, so `.primary`/`.secondary` text always
        // matches the DDTheme surfaces being drawn.
        .colorScheme(theme.isDark ? .dark : .light)
        .animation(Self.springMotion, value: windowHeight)
        .onPreferenceChange(ContentHeightKey.self) { height in
            guard height > 0 else { return }
            withAnimation(Self.springMotion) { measuredHeight = height }
        }
        .task {
            viewModel.restoreLogin()
            viewModel.promptForSavedQueueIfNeeded()
        }
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(spacing: 14) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                Text(tr("Welcome to ", "ยินดีต้อนรับสู่ "))
                Text("Drop").foregroundStyle(.primary)
                Text("Drive").foregroundStyle(DDTheme.accent)
            }
            .font(.dd(17, .bold))

            VStack(alignment: .leading, spacing: 12) {
                welcomeStep(1, tr("The app lives up here in the menu bar — there's no Dock icon.", "แอพอยู่บนเมนูบาร์ตรงนี้ ↑ ไม่มีไอคอนใน Dock"))
                welcomeStep(2, tr("Paste a Drive or video link — one or many at a time.", "วางลิงก์ Drive หรือวิดีโอ จะวางทีละลิงก์หรือหลายลิงก์ก็ได้"))
                welcomeStep(3, tr("Review the destination, then start the queue when you're ready.", "ตรวจปลายทาง แล้วเริ่มคิวเมื่อพร้อม"))
            }
            .padding(.horizontal, 8)

            Button {
                hasSeenWelcome = true
            } label: {
                Text(tr("Get started", "เริ่มใช้เลย"))
                    .font(.dd(13, .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DDTheme.accent))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
        .padding(20)
    }

    private func welcomeStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.dd(11, .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(DDTheme.accent))

            Text(text)
                .font(.dd(13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Top bar

    /// Slim header: the app logo and wordmark on the left, live status, and the
    /// account control on the right. Shown above every pane.
    private var topBar: some View {
        HStack(spacing: 8) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 17, height: 17)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                Text("Drop").foregroundStyle(.primary)
                Text("Drive").foregroundStyle(DDTheme.accent)
            }
            .font(.dd(13, .bold))
            .accessibilityElement()
            .accessibilityLabel("DropDrive")

            statusPill

            Spacer()

            HeaderAccountButton(
                account: viewModel.googleAccount,
                isSigningIn: viewModel.isSigningIn,
                isLocked: viewModel.isQueueProcessing,
                onSignIn: viewModel.signInWithGoogle,
                onSignOut: viewModel.signOut
            )

            Button(action: SettingsWindow.show) {
                Image(systemName: "gearshape")
                    .font(.dd(13))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(tr("Settings", "การตั้งค่า"))
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Bottom tab bar

    private var bottomTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Pane.allCases) { pane in
                tabButton(pane)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DDTheme.rail)
    }

    private func tabButton(_ pane: Pane) -> some View {
        Button {
            withAnimation(Self.springMotion) { selectedPane = pane }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: pane.icon)
                    .font(.dd(13, .medium))
                    .overlay(alignment: .topTrailing) {
                        if pane == .queue, activeCount > 0 {
                            Circle()
                                .fill(DDTheme.accent)
                                .frame(width: 5, height: 5)
                                .offset(x: 4, y: -3)
                        }
                    }
                if selectedPane == pane {
                    Text(pane.title)
                        .font(.dd(11, .medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(selectedPane == pane ? DDTheme.accent : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selectedPane == pane ? DDTheme.accentSoft : .clear)
            )
            .contentShape(Rectangle())
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
        }
    }

    private var queuePane: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        UpdateBanner()

                        DownloadFormView(
                            driveLink: $viewModel.driveLink,
                            destinationURL: viewModel.selectedDestinationURL,
                            isLocked: viewModel.isSigningIn,
                            hasActiveCard: viewModel.hasActiveAnalysisCard,
                            onChooseDestination: viewModel.chooseDestinationFolder,
                            onSelectDestination: viewModel.selectDestinationFolder,
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
                                onPauseActive: viewModel.pauseQueue,
                                onResumePaused: viewModel.resumeQueue,
                                onRevealInFinder: { item in
                                    guard let url = item.resultURL else { return }
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                },
                                onOpen: { item in
                                    guard let url = item.resultURL else { return }
                                    NSWorkspace.shared.open(url)
                                },
                                onCopyLink: { item in
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(item.driveLink, forType: .string)
                                },
                                onDownloadAgain: viewModel.downloadAgain,
                                onClearCompleted: viewModel.clearCompletedQueueItems,
                                onPauseQueue: viewModel.pauseQueue,
                                onResumeQueue: viewModel.resumeQueue,
                                onReorder: viewModel.moveQueueItem
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        } else if viewModel.linkAnalysisState == .idle {
                            // Resolved once per redraw and handed down, rather
                            // than recomputed for the emptiness check and again
                            // for the rows.
                            let recent = recentCompleted
                            if !recent.isEmpty {
                                recentPreview(recent).transition(.opacity)
                            }
                        }
                    }
                    .padding(DDMetrics.contentInset)
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
        // Live numbers while something is moving: the header is on screen in
        // every pane, so it is the one place that can say the app is working
        // without the user going back to the queue to check.
        if viewModel.isQueueProcessing {
            let speed = viewModel.activeProgress?.bytesPerSecond ?? 0
            if speed > 0 {
                return "\(Formatters.transferSpeed(speed))"
            }
            return tr("Downloading…", "กำลังดาวน์โหลด…")
        }
        let today = historyStore.totals.completedToday
        if today > 0 { return tr("\(today) today", "วันนี้ \(today) รายการ") }
        return tr("Ready", "พร้อมใช้งาน")
    }

    private var statusPill: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.isQueueProcessing ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                .font(.dd(9, .semibold))
            Text(headerStatus)
                .font(.dd(10, .medium))
                .lineLimit(1)
        }
        .foregroundStyle(viewModel.isQueueProcessing ? DDTheme.accent : DDTheme.success)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule().fill((viewModel.isQueueProcessing ? DDTheme.accent : DDTheme.success).opacity(0.12))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headerStatus)
    }

    /// Only ever shown three at a time, so the scan stops there rather than
    /// filtering all 50 history entries — twice — on every redraw.
    private var recentCompleted: [DownloadHistoryItem] {
        var found: [DownloadHistoryItem] = []
        found.reserveCapacity(3)
        for item in historyStore.items {
            guard item.status == .completed, let url = item.itemURL else { continue }
            // A row whose file was deleted or moved would have a dead Open
            // button — leave it to the full Recent pane instead. Read through
            // the cache: this runs on every redraw, and hitting the filesystem
            // here stutters the window.
            guard statusCache.status(for: url)?.exists ?? true else { continue }
            found.append(item)
            if found.count == 3 { break }
        }
        return found
    }

    /// Fills the empty-queue space with something useful: the last few finished
    /// downloads, openable in place, with a jump to the full Recent pane.
    private func recentPreview(_ items: [DownloadHistoryItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tr("Recent", "ล่าสุด"))
                    .font(.dd(11, .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)

                Spacer()

                Button(tr("All downloads", "ดูทั้งหมด")) {
                    withAnimation(Self.springMotion) { selectedPane = .recent }
                }
                    .buttonStyle(.plain)
                    .font(.dd(11))
                    .foregroundStyle(DDTheme.accent)
                    .accessibilityLabel("Show all downloads")
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
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
                .font(.dd(13))
                .foregroundStyle(.green)

            Text(item.name)
                .font(.dd(11))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button(tr("Open", "เปิด")) {
                guard let url = item.itemURL else { return }
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.plain)
            .font(.dd(11, .medium))
            .foregroundStyle(DDTheme.accent)
            .accessibilityLabel("Open \(item.name)")

            Button {
                guard let url = item.itemURL else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
                    .font(.dd(11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(tr("Reveal in Finder", "เปิดใน Finder"))
            .accessibilityLabel("Reveal \(item.name) in Finder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var analysisArea: some View {
        switch viewModel.linkAnalysisState {
        case .idle:
            EmptyView()
        case .invalidLink:
            LinkInvalidView(link: viewModel.driveLink, onClear: viewModel.cancelAnalysis)
        case .analyzing:
            LinkAnalyzingView()
        case .needsConnection:
            LinkNeedsConnectionView(isSigningIn: viewModel.isSigningIn, onConnect: viewModel.signInWithGoogle)
        case .analyzed(let analysis):
            AnalyzedPromptView(
                analysis: analysis,
                destinationURL: viewModel.selectedDestinationURL,
                preflight: viewModel.preflight(for: analysis),
                sourceLink: viewModel.driveLink,
                onChooseDestination: viewModel.chooseDestinationFolder,
                onSelectDestination: viewModel.selectDestinationFolder,
                onDownload: { asAudio, clipSection, customName in
                    viewModel.confirmAnalyzedDownload(asAudio: asAudio, clipSection: clipSection, customName: customName)
                },
                onCancel: viewModel.cancelAnalysis
            )
            // Stable identity across the background enrichment that replaces a
            // video's analysis ~12s in: without it SwiftUI builds a new view and
            // resets its @State, silently reverting an MP3 or trim choice the
            // user had already made.
            .id(analysis.itemID)
        case .batchReview(let items):
            BatchReviewView(
                items: items,
                destinationURL: viewModel.selectedDestinationURL,
                onChooseDestination: viewModel.chooseDestinationFolder,
                onSelectDestination: viewModel.selectDestinationFolder,
                onToggle: viewModel.toggleBatchSelection,
                onAdd: viewModel.addSelectedBatchToQueue,
                onCancel: viewModel.cancelAnalysis
            )
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
                            onRemoveItem: { historyStore.remove($0) },
                            onClearHistory: { historyStore.clear() }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
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
        ScrollView {
            StatisticsSection()
                .padding(DDMetrics.contentInset)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
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

// MARK: - Header account button

/// A small account control in the window's top-right corner — the profile
/// avatar (or a person glyph when signed out). Tap for account details and
/// disconnect, or a connect prompt.
private struct HeaderAccountButton: View {
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
        .help(account?.email ?? tr("Connect Google Drive", "เชื่อมต่อ Google Drive"))
        .accessibilityLabel(account.map { "Account: \($0.name)" } ?? "Connect Google Drive")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            // The popover chrome is drawn by AppKit in the SYSTEM appearance,
            // but its SwiftUI content inherits the main window's forced-light
            // environment — black text on a dark popover. Resolve the actual
            // system appearance and pin the content to it explicitly.
            popoverContent
                .colorScheme(systemColorScheme)
        }
    }

    /// The real system appearance, not the light scheme the presenting window
    /// forces on its environment. Evaluated when the popover opens.
    private var systemColorScheme: ColorScheme {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
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
            .frame(width: 22, height: 22)
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(DDTheme.border, lineWidth: 0.5) }
        } else {
            Image(systemName: "person.crop.circle")
                .font(.dd(17))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
        }
    }

    private func initialCircle(_ text: String) -> some View {
        Circle()
            .fill(DDTheme.accent)
            .overlay {
                Text(text)
                    .font(.dd(11, .semibold))
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
                            .font(.dd(13, .semibold))
                        Text(account.email)
                            .font(.dd(11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Divider()

                Button {
                    NSWorkspace.shared.open(URL(string: "https://myaccount.google.com/permissions")!)
                } label: {
                    Text(tr("Manage Connection", "จัดการการเชื่อมต่อ"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    showPopover = false
                    onSignOut()
                } label: {
                    Text(tr("Disconnect", "ยกเลิกการเชื่อมต่อ"))
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
                Text(tr("Connect your Google account to download private files and folders.", "เชื่อมต่อบัญชี Google เพื่อดาวน์โหลดไฟล์และโฟลเดอร์ส่วนตัว"))
                    .font(.dd(11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(tr("Continue with Google", "เข้าสู่ระบบด้วย Google")) {
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

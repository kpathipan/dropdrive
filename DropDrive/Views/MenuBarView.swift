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
            case .queue: tr("Queue", "คิวดาวน์โหลด")
            case .recent: tr("Recent", "ล่าสุด")
            case .stats: tr("Statistics", "สถิติ")
            case .prefs: tr("Preferences", "ตั้งค่า")
            }
        }
    }

    @State private var viewModel = DropDriveViewModel.shared
    @State private var historyStore = DownloadHistoryStore.shared
    @State private var selectedPane: Pane = .queue
    @State private var isDropTargeted = false
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
    private static let chromeAllowance: CGFloat = 29 + 33
    private static let maxWindowHeight: CGFloat = 480
    private static let minWindowHeight: CGFloat = 130

    private var windowHeight: CGFloat {
        let raw: CGFloat
        switch selectedPane {
        case .queue, .recent:
            raw = measuredHeight + Self.chromeAllowance
        case .stats:
            raw = 250
        case .prefs:
            raw = 420
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
        .frame(width: 340, height: hasSeenWelcome ? windowHeight : 320)
        .font(.dd(13))
        .background(DDTheme.canvas)
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
            .font(.dd(16, .bold))

            VStack(alignment: .leading, spacing: 12) {
                welcomeStep(1, tr("The app lives up here in the menu bar — there's no Dock icon.", "แอพอยู่บนเมนูบาร์ตรงนี้ ↑ ไม่มีไอคอนใน Dock"))
                welcomeStep(2, tr("Copy a Google Drive link and paste it in the box.", "ก๊อปลิงก์ Google Drive มาวางในช่อง"))
                welcomeStep(3, tr("Pick a download folder once — it's remembered.", "ตั้งโฟลเดอร์ปลายทางครั้งเดียว จำให้ตลอด"))
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
                .font(.dd(12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Top bar

    /// Slim header: the app logo and wordmark on the left, live status, and the
    /// account control on the right. Shown above every pane.
    private var topBar: some View {
        HStack(spacing: 7) {
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

            Text(headerStatus)
                .font(.dd(10))
                .foregroundStyle(.secondary)

            Spacer()

            HeaderAccountButton(
                account: viewModel.googleAccount,
                isSigningIn: viewModel.isSigningIn,
                isLocked: viewModel.isQueueProcessing,
                onSignIn: viewModel.signInWithGoogle,
                onSignOut: viewModel.signOut
            )
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
    }

    // MARK: - Bottom tab bar

    private var bottomTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Pane.allCases) { pane in
                tabButton(pane)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
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
                        .font(.dd(9.5, .medium))
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
        case .prefs:
            PreferencesView().transition(.opacity)
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
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
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
        if viewModel.isQueueProcessing { return tr("Downloading…", "กำลังดาวน์โหลด…") }
        let today = historyStore.totals.completedToday
        if today > 0 { return tr("\(today) today", "วันนี้ \(today) รายการ") }
        return tr("Ready", "พร้อมใช้งาน")
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
                    .font(.dd(10.5, .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)

                Spacer()

                Button(tr("All downloads", "ดูทั้งหมด")) {
                    withAnimation(Self.springMotion) { selectedPane = .recent }
                }
                    .buttonStyle(.plain)
                    .font(.dd(10.5))
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
                .font(.dd(12))
                .foregroundStyle(.green)

            Text(item.name)
                .font(.dd(11.5))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button(tr("Open", "เปิด")) {
                guard let url = item.itemURL else { return }
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.plain)
            .font(.dd(10.5, .medium))
            .foregroundStyle(DDTheme.accent)
            .accessibilityLabel("Open \(item.name)")

            Button {
                guard let url = item.itemURL else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
                    .font(.dd(10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(tr("Reveal in Finder", "เปิดใน Finder"))
            .accessibilityLabel("Reveal \(item.name) in Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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
        case .analyzed(let analysis):
            AnalyzedPromptView(
                analysis: analysis,
                destinationURL: viewModel.selectedDestinationURL,
                onChooseDestination: viewModel.chooseDestinationFolder,
                onDownload: { asAudio, clipSection in
                    viewModel.confirmAnalyzedDownload(asAudio: asAudio, clipSection: clipSection)
                },
                onCancel: viewModel.cancelAnalysis
            )
            // Stable identity across the background enrichment that replaces a
            // video's analysis ~12s in: without it SwiftUI builds a new view and
            // resets its @State, silently reverting an MP3 or trim choice the
            // user had already made.
            .id(analysis.itemID)
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
                .font(.dd(16))
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
                            .font(.dd(12, .semibold))
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
                    .font(.dd(11.5))
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

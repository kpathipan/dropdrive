import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum FolderBrowserLayout: String, CaseIterable {
    case gallery
    case list
}

private enum FolderBrowserSize: String, CaseIterable {
    case small
    case medium
    case large

    var cardWidth: CGFloat {
        switch self {
        case .small: 92
        case .medium: 128
        case .large: 168
        }
    }

    var artworkHeight: CGFloat {
        switch self {
        case .small: 60
        case .medium: 82
        case .large: 108
        }
    }

    var rowHeight: CGFloat {
        switch self {
        case .small: 36
        case .medium: 46
        case .large: 58
        }
    }

    var iconSide: CGFloat {
        switch self {
        case .small: 22
        case .medium: 28
        case .large: 34
        }
    }

    var shortLabel: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }
}

/// Selectable Drive folder contents with two stable layouts and three density
/// levels. Gallery deliberately separates visual media from other file types;
/// List keeps one scan-friendly order while retaining small media artwork.
struct FolderItemBrowser: View {
    let folderID: String
    let items: [DriveLinkAnalysis.FolderItem]
    @Binding var selectedFileIDs: Set<String>?

    @AppStorage("folderBrowser.layout") private var layoutRaw = FolderBrowserLayout.gallery.rawValue
    @AppStorage("folderBrowser.gallerySize") private var gallerySizeRaw = FolderBrowserSize.medium.rawValue
    @AppStorage("folderBrowser.listSize") private var listSizeRaw = FolderBrowserSize.medium.rawValue
    @State private var focusedItemID: String?
    @State private var previewedItem: DriveLinkAnalysis.FolderItem?
    @State private var searchText = ""
    @State private var snapshotStore = DriveFolderSnapshotStore.shared
    @FocusState private var browserFocused: Bool

    private var layout: FolderBrowserLayout {
        FolderBrowserLayout(rawValue: layoutRaw) ?? .gallery
    }

    private var currentSize: FolderBrowserSize {
        FolderBrowserSize(rawValue: layout == .gallery ? gallerySizeRaw : listSizeRaw) ?? .medium
    }

    private var currentSizeBinding: Binding<String> {
        Binding(
            get: { layout == .gallery ? gallerySizeRaw : listSizeRaw },
            set: { value in
                if layout == .gallery { gallerySizeRaw = value }
                else { listSizeRaw = value }
            }
        )
    }

    private var visualItems: [DriveLinkAnalysis.FolderItem] {
        filteredItems.filter { $0.category == .images || $0.category == .videos }
    }

    private var otherItems: [DriveLinkAnalysis.FolderItem] {
        filteredItems.filter { $0.category != .images && $0.category != .videos }
    }

    private var filteredItems: [DriveLinkAnalysis.FolderItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.relativePath.localizedCaseInsensitiveContains(query)
                || $0.mimeType.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedCount: Int {
        effectiveSelectedIDs.count
    }

    private var allItemIDs: Set<String> { Set(items.map(\.id)) }

    private var effectiveSelectedIDs: Set<String> {
        FolderSelectionSemantics.effectiveSelection(
            selectedIDs: selectedFileIDs,
            allIDs: allItemIDs
        )
    }

    private var selectedBytes: Int64 {
        let selected = effectiveSelectedIDs
        return items.reduce(0) { total, item in
            guard selected.contains(item.id) else { return total }
            return total + (item.size ?? 0)
        }
    }

    private var selectionState: SelectionState {
        if selectedCount == items.count { return .all }
        if selectedCount == 0 { return .none }
        return .some
    }

    private var diffSummary: DriveFolderSnapshotStore.Summary {
        snapshotStore.summary(folderID: folderID, items: items)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controls
            selectionSummary
            if diffSummary.hasHistory {
                folderDiffSummary
            }
            if items.count > 30 {
                searchField
            }

            Group {
                if let previewedItem {
                    DriveItemPreview(item: previewedItem) {
                        withAnimation(.easeOut(duration: 0.14)) { self.previewedItem = nil }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else if filteredItems.isEmpty {
                    ContentUnavailableView(
                        tr("No matching files", "ไม่พบไฟล์"),
                        systemImage: "magnifyingglass",
                        description: Text(tr("Try another search.", "ลองค้นหาด้วยคำอื่น"))
                    )
                } else if layout == .gallery {
                    gallery
                } else {
                    list
                }
            }
            .frame(height: 238, alignment: .top)
        }
        .focusable()
        .focused($browserFocused)
        .onKeyPress(.space) {
            guard let focusedItemID,
                  let item = items.first(where: { $0.id == focusedItemID }) else { return .ignored }
            withAnimation(.easeOut(duration: 0.14)) {
                previewedItem = previewedItem == nil ? item : nil
            }
            return .handled
        }
        .onKeyPress(.return) {
            guard let item = focusedItem else { return .ignored }
            selectAndFocus(item)
            return .handled
        }
        .onKeyPress(.rightArrow) { moveFocus(by: 1) }
        .onKeyPress(.downArrow) { moveFocus(by: 1) }
        .onKeyPress(.leftArrow) { moveFocus(by: -1) }
        .onKeyPress(.upArrow) { moveFocus(by: -1) }
        .onExitCommand {
            if previewedItem != nil { previewedItem = nil }
        }
        .onAppear {
            focusedItemID = focusedItemID ?? items.first?.id
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("Choose files to download", "เลือกไฟล์ที่จะดาวน์โหลด"))
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: toggleAll) {
                Label {
                    Text(tr("Select all", "เลือกทั้งหมด"))
                        .font(.dd(10, .medium))
                } icon: {
                    Image(systemName: selectionState.symbol)
                        .foregroundStyle(selectionState == .none ? Color.secondary : DDTheme.accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityValue(selectionState.accessibilityValue)

            Spacer(minLength: 4)

            Picker(tr("Layout", "รูปแบบ"), selection: $layoutRaw) {
                Image(systemName: "square.grid.2x2").tag(FolderBrowserLayout.gallery.rawValue)
                    .accessibilityLabel(tr("Gallery", "การ์ด"))
                Image(systemName: "list.bullet").tag(FolderBrowserLayout.list.rawValue)
                    .accessibilityLabel(tr("List", "รายการ"))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 72)

            Picker(tr("Size", "ขนาด"), selection: currentSizeBinding) {
                ForEach(FolderBrowserSize.allCases, id: \.self) { size in
                    Text(size.shortLabel).tag(size.rawValue)
                        .accessibilityLabel(size.accessibilityLabel)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 94)
        }
    }

    private var selectionSummary: some View {
        HStack(spacing: 4) {
            Text(tr(
                "Selected \(selectedCount) of \(items.count)",
                "เลือก \(selectedCount) จาก \(items.count) ไฟล์"
            ))
            if items.contains(where: { $0.size != nil }) {
                Text("·")
                Text(Formatters.byteCount(selectedBytes))
            }
        }
        .font(.dd(10, .medium).monospacedDigit())
        .foregroundStyle(selectedCount == 0 ? Color.orange : Color.secondary)
        .accessibilityElement(children: .combine)
    }

    private var folderDiffSummary: some View {
        HStack(spacing: 6) {
            Label(tr("New \(diffSummary.newCount)", "ใหม่ \(diffSummary.newCount)"), systemImage: "sparkles")
                .foregroundStyle(DDTheme.success)
            if diffSummary.changedCount > 0 {
                Text("·")
                Text(tr("Changed \(diffSummary.changedCount)", "เปลี่ยน \(diffSummary.changedCount)"))
                    .foregroundStyle(.orange)
            }
            Text("·")
            Text(tr("Downloaded \(diffSummary.downloadedCount)", "โหลดแล้ว \(diffSummary.downloadedCount)"))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button(tr("Select new", "เลือกไฟล์ใหม่")) {
                let ids = snapshotStore.newOrChangedIDs(folderID: folderID, items: items)
                selectedFileIDs = ids.count == items.count ? nil : ids
            }
            .buttonStyle(.plain)
            .font(.dd(10, .semibold))
            .foregroundStyle(DDTheme.accent)
        }
        .font(.dd(9, .medium).monospacedDigit())
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(DDTheme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.dd(10))
                .foregroundStyle(.secondary)
            TextField(tr("Search files", "ค้นหาไฟล์"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.dd(10))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Clear search", "ล้างการค้นหา"))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(DDTheme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(DDTheme.border, lineWidth: 0.5)
        }
    }

    private var gallery: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if !visualItems.isEmpty {
                    sectionLabel(tr("Photos & videos", "รูปภาพและวิดีโอ"), count: visualItems.count)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: currentSize.cardWidth, maximum: currentSize.cardWidth), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(visualItems) { item in galleryTile(item, usesThumbnail: true) }
                    }
                }

                if !otherItems.isEmpty {
                    sectionLabel(tr("Other files", "ไฟล์อื่น"), count: otherItems.count)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: currentSize.cardWidth, maximum: currentSize.cardWidth), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(otherItems) { item in galleryTile(item, usesThumbnail: false) }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredItems) { item in listRow(item) }
            }
            .padding(.vertical, 2)
        }
    }

    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.dd(10, .semibold)).foregroundStyle(.secondary)
            Spacer()
            Text("\(count)").font(.dd(10).monospacedDigit()).foregroundStyle(.tertiary)
        }
    }

    private func galleryTile(_ item: DriveLinkAnalysis.FolderItem, usesThumbnail: Bool) -> some View {
        let selected = isSelected(item.id)
        return ZStack(alignment: .topTrailing) {
            Button { selectAndFocus(item) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        if usesThumbnail {
                            DriveThumbnailArtwork(item: item, contentMode: .fill)
                        } else {
                            DriveFileIcon(item: item, side: currentSize.iconSide)
                        }
                    }
                    .frame(width: currentSize.cardWidth, height: currentSize.artworkHeight)
                    .background(DDTheme.rail)
                    .clipped()

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.dd(currentSize == .small ? 10 : 11, .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if currentSize != .small {
                            Text(item.size.map(Formatters.byteCount) ?? tr("Unknown size", "ไม่ทราบขนาด"))
                                .font(.dd(9).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(7)
                    .frame(width: currentSize.cardWidth, alignment: .leading)
                }
                .background(DDTheme.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? DDTheme.accent : DDTheme.border, lineWidth: selected ? 1.5 : 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(itemAccessibilityLabel(item, selected: selected))
            .help(item.relativePath)

            VStack(spacing: 4) {
                Button { selectAndFocus(item) } label: {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .font(.dd(12, .semibold))
                        .foregroundStyle(selected ? DDTheme.accent : Color.white)
                        .shadow(color: .black.opacity(0.35), radius: 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selected
                    ? tr("Deselect \(item.name)", "ยกเลิกการเลือก \(item.name)")
                    : tr("Select \(item.name)", "เลือก \(item.name)"))

                Button { preview(item) } label: {
                    Image(systemName: "eye.fill")
                        .font(.dd(9, .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(.black.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .help(tr("Preview (Space)", "ดูตัวอย่าง (Space)"))
                .accessibilityLabel(tr("Preview \(item.name)", "ดูตัวอย่าง \(item.name)"))

                PromiseDragHandle(item: item)
                    .frame(width: 20, height: 20)
                    .help(tr("Drag to Finder", "ลากไปยัง Finder"))
            }
            .padding(5)

            if let badge = diffBadge(for: item) {
                Text(badge.text)
                    .font(.dd(8, .bold))
                    .foregroundStyle(badge.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(DDTheme.canvas.opacity(0.86)))
                    .padding(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            if hovering { focusedItemID = item.id }
        }
        .contextMenu {
            Button(tr("Preview", "ดูตัวอย่าง")) { preview(item) }
            Button(selected ? tr("Deselect", "ยกเลิกการเลือก") : tr("Select", "เลือก")) { selectAndFocus(item) }
        }
    }

    private func listRow(_ item: DriveLinkAnalysis.FolderItem) -> some View {
        let selected = isSelected(item.id)
        let visual = item.category == .images || item.category == .videos
        return HStack(spacing: 7) {
            Button { selectAndFocus(item) } label: {
                HStack(spacing: 7) {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(selected ? DDTheme.accent : Color.secondary)

                    Group {
                        if visual {
                            DriveThumbnailArtwork(item: item, contentMode: .fill)
                        } else {
                            DriveFileIcon(item: item, side: currentSize.iconSide)
                        }
                    }
                    .frame(width: currentSize.rowHeight - 10, height: currentSize.rowHeight - 10)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.relativePath)
                            .font(.dd(currentSize == .small ? 10 : 11, .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if currentSize == .large {
                            Text(item.mimeType)
                                .font(.dd(9))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)
                    if let badge = diffBadge(for: item) {
                        Text(badge.text)
                            .font(.dd(8, .bold))
                            .foregroundStyle(badge.color)
                    }
                    if let size = item.size {
                        Text(Formatters.byteCount(size))
                            .font(.dd(9).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: currentSize.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { preview(item) } label: {
                Image(systemName: "eye")
                    .font(.dd(10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(tr("Preview (Space)", "ดูตัวอย่าง (Space)"))

            PromiseDragHandle(item: item)
                .frame(width: 20, height: 20)
                .help(tr("Drag to Finder", "ลากไปยัง Finder"))
        }
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(focusedItemID == item.id ? DDTheme.accentSoft : Color.clear)
        )
        .onHover { hovering in
            if hovering { focusedItemID = item.id }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(itemAccessibilityLabel(item, selected: selected))
    }

    private func selectAndFocus(_ item: DriveLinkAnalysis.FolderItem) {
        focusedItemID = item.id
        browserFocused = true
        selectedFileIDs = FolderSelectionSemantics.toggling(
            id: item.id,
            selectedIDs: selectedFileIDs,
            allIDs: allItemIDs
        )
    }

    private func preview(_ item: DriveLinkAnalysis.FolderItem) {
        focusedItemID = item.id
        browserFocused = true
        withAnimation(.easeOut(duration: 0.14)) { previewedItem = item }
    }

    private func isSelected(_ id: String) -> Bool {
        effectiveSelectedIDs.contains(id)
    }

    private var focusedItem: DriveLinkAnalysis.FolderItem? {
        guard let focusedItemID else { return filteredItems.first }
        return filteredItems.first(where: { $0.id == focusedItemID }) ?? filteredItems.first
    }

    private func toggleAll() {
        selectedFileIDs = selectionState == .all ? [] : nil
        browserFocused = true
    }

    private func moveFocus(by offset: Int) -> KeyPress.Result {
        guard !filteredItems.isEmpty else { return .ignored }
        let currentIndex = focusedItemID.flatMap { id in filteredItems.firstIndex(where: { $0.id == id }) } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), filteredItems.count - 1)
        focusedItemID = filteredItems[nextIndex].id
        if previewedItem != nil { previewedItem = filteredItems[nextIndex] }
        return .handled
    }

    private enum SelectionState: Equatable {
        case all, some, none

        var symbol: String {
            switch self {
            case .all: "checkmark.square.fill"
            case .some: "minus.square.fill"
            case .none: "square"
            }
        }

        var accessibilityValue: String {
            switch self {
            case .all: tr("All selected", "เลือกทั้งหมดแล้ว")
            case .some: tr("Some selected", "เลือกบางไฟล์")
            case .none: tr("None selected", "ยังไม่ได้เลือก")
            }
        }
    }

    private func itemAccessibilityLabel(_ item: DriveLinkAnalysis.FolderItem, selected: Bool) -> String {
        let state = selected ? tr("Selected", "เลือกแล้ว") : tr("Not selected", "ยังไม่เลือก")
        return "\(item.relativePath), \(state)"
    }

    private func diffBadge(for item: DriveLinkAnalysis.FolderItem) -> (text: String, color: Color)? {
        switch snapshotStore.state(folderID: folderID, item: item) {
        case .new: (tr("NEW", "ใหม่"), DDTheme.success)
        case .changed: (tr("CHANGED", "เปลี่ยน"), .orange)
        case .downloaded: (tr("DONE", "โหลดแล้ว"), .secondary)
        case .unknown: nil
        }
    }
}

/// Finder asks an NSFilePromiseProvider to write straight into the folder where
/// the user drops. Unlike a generic item provider, this never downloads a full
/// second copy into DropDrive's temporary directory first.
@MainActor
private enum DriveFilePromise {
    static func provider(for item: DriveLinkAnalysis.FolderItem) -> NSFilePromiseProvider {
        let delegate = DriveFilePromiseDelegate(
            item: item,
            service: GoogleDriveDownloadService(loginManager: LoginManager.shared)
        )
        return RetainedFilePromiseProvider(
            fileType: promisedType(for: item),
            delegate: delegate,
            retainedDelegate: delegate
        )
    }

    private static func promisedType(for item: DriveLinkAnalysis.FolderItem) -> String {
        if item.mimeType == "application/vnd.google-apps.document" { return UTType(filenameExtension: "docx")?.identifier ?? UTType.data.identifier }
        if item.mimeType == "application/vnd.google-apps.spreadsheet" { return UTType(filenameExtension: "xlsx")?.identifier ?? UTType.data.identifier }
        if item.mimeType == "application/vnd.google-apps.presentation" { return UTType(filenameExtension: "pptx")?.identifier ?? UTType.data.identifier }
        if item.mimeType == "application/vnd.google-apps.drawing" { return UTType.png.identifier }
        return (UTType(mimeType: item.mimeType)
                ?? UTType(filenameExtension: (item.name as NSString).pathExtension)
                ?? .data).identifier
    }
}

private struct PromiseDragHandle: NSViewRepresentable {
    let item: DriveLinkAnalysis.FolderItem

    func makeNSView(context: Context) -> PromiseDragView {
        PromiseDragView(item: item)
    }

    func updateNSView(_ nsView: PromiseDragView, context: Context) {
        nsView.item = item
    }
}

@MainActor
private final class PromiseDragView: NSImageView, NSDraggingSource {
    var item: DriveLinkAnalysis.FolderItem

    init(item: DriveLinkAnalysis.FolderItem) {
        self.item = item
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: tr("Drag to Finder", "ลากไปยัง Finder"))
        contentTintColor = .secondaryLabelColor
        imageScaling = .scaleProportionallyDown
        toolTip = tr("Drag to Finder", "ลากไปยัง Finder")
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDragged(with event: NSEvent) {
        let provider = DriveFilePromise.provider(for: item)
        let draggingItem = NSDraggingItem(pasteboardWriter: provider)
        let dragImage = DriveFileTypeIcon.image(for: item)
        draggingItem.setDraggingFrame(bounds, contents: dragImage)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

@MainActor
private final class RetainedFilePromiseProvider: NSFilePromiseProvider {
    private let retainedDelegate: DriveFilePromiseDelegate

    init(fileType: String, delegate: DriveFilePromiseDelegate, retainedDelegate: DriveFilePromiseDelegate) {
        self.retainedDelegate = retainedDelegate
        super.init(fileType: fileType, delegate: delegate)
    }

    required init?(coder: NSCoder) { nil }
}

private nonisolated final class DriveFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    private let item: DriveLinkAnalysis.FolderItem
    private let service: any DownloadServicing
    private let queue = OperationQueue()

    init(item: DriveLinkAnalysis.FolderItem, service: any DownloadServicing) {
        self.item = item
        self.service = service
        queue.name = "DropDrive.FinderPromise"
        queue.maxConcurrentOperationCount = 1
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        let base = (item.name as NSString).deletingPathExtension
        if item.mimeType == "application/vnd.google-apps.document" { return "\(base).docx" }
        if item.mimeType == "application/vnd.google-apps.spreadsheet" { return "\(base).xlsx" }
        if item.mimeType == "application/vnd.google-apps.presentation" { return "\(base).pptx" }
        if item.mimeType == "application/vnd.google-apps.drawing" { return "\(base).png" }
        return item.name
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let item = self.item
        let service = self.service
        Task {
            do {
                _ = try await service.download(
                    DownloadRequest(
                        driveLink: "https://drive.google.com/file/d/\(item.id)/view",
                        itemID: item.id,
                        destinationURL: url,
                        resourceKey: item.resourceKey,
                        customName: (item.name as NSString).deletingPathExtension
                    ),
                    progress: { _ in }
                )
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { queue }
}

private extension FolderBrowserSize {
    var accessibilityLabel: String {
        switch self {
        case .small: tr("Small", "เล็ก")
        case .medium: tr("Medium", "กลาง")
        case .large: tr("Large", "ใหญ่")
        }
    }
}

private struct DriveThumbnailArtwork: View {
    let item: DriveLinkAnalysis.FolderItem
    let contentMode: ContentMode
    @State private var model = DriveThumbnailModel()

    var body: some View {
        ZStack {
            DDTheme.rail
            if let image = model.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if model.isLoading {
                ProgressView().controlSize(.small)
            } else {
                DriveFileIcon(item: item, side: 30)
            }
        }
        .task(id: "\(item.id):\(item.thumbnailVersion ?? "current")") {
            model.load(item: item)
        }
    }
}

private struct DriveFileIcon: View {
    let item: DriveLinkAnalysis.FolderItem
    let side: CGFloat

    var body: some View {
        ZStack {
            DDTheme.rail
            Image(nsImage: DriveFileTypeIcon.image(for: item))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: side, height: side)
        }
    }
}

@MainActor
private enum DriveFileTypeIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for item: DriveLinkAnalysis.FolderItem) -> NSImage {
        let key = "\(item.mimeType)|\((item.name as NSString).pathExtension.lowercased())"
        if let cached = cache[key] { return cached }
        let type = UTType(mimeType: item.mimeType)
            ?? UTType(filenameExtension: (item.name as NSString).pathExtension)
            ?? .data
        let image = NSWorkspace.shared.icon(for: type)
        cache[key] = image
        return image
    }
}

private struct DriveItemPreview: View {
    let item: DriveLinkAnalysis.FolderItem
    let onClose: () -> Void

    private var isVisual: Bool {
        item.category == .images || item.category == .videos
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(tr("Preview", "ดูตัวอย่าง"), systemImage: "eye.fill")
                    .font(.dd(11, .semibold))
                Spacer()
                Text("Space")
                    .font(.dd(9, .medium).monospaced())
                    .foregroundStyle(.tertiary)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Close preview", "ปิดตัวอย่าง"))
            }

            Group {
                if isVisual {
                    DriveThumbnailArtwork(item: item, contentMode: .fit)
                } else {
                    DriveFileIcon(item: item, side: 64)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 148)
            .background(DDTheme.rail)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text(item.name)
                .font(.dd(12, .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 5) {
                Text(item.size.map(Formatters.byteCount) ?? tr("Unknown size", "ไม่ทราบขนาด"))
                Text("·")
                Text(item.mimeType)
            }
            .font(.dd(10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(10)
        .background(DDTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DDTheme.accent.opacity(0.35), lineWidth: 1)
        }
    }
}

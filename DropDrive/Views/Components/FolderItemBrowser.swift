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
    let items: [DriveLinkAnalysis.FolderItem]
    @Binding var selectedFileIDs: Set<String>?

    @AppStorage("folderBrowser.layout") private var layoutRaw = FolderBrowserLayout.gallery.rawValue
    @AppStorage("folderBrowser.gallerySize") private var gallerySizeRaw = FolderBrowserSize.medium.rawValue
    @AppStorage("folderBrowser.listSize") private var listSizeRaw = FolderBrowserSize.medium.rawValue
    @State private var focusedItemID: String?
    @State private var previewedItem: DriveLinkAnalysis.FolderItem?
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
        items.filter { $0.category == .images || $0.category == .videos }
    }

    private var otherItems: [DriveLinkAnalysis.FolderItem] {
        items.filter { $0.category != .images && $0.category != .videos }
    }

    private var selectedCount: Int {
        selectedFileIDs?.count ?? items.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controls
            quickSelections

            Group {
                if let previewedItem {
                    DriveItemPreview(item: previewedItem) {
                        withAnimation(.easeOut(duration: 0.14)) { self.previewedItem = nil }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
            Text(tr("Selected (selectedCount)", "เลือก (selectedCount)"))
                .font(.dd(10, .medium).monospacedDigit())
                .foregroundStyle(.secondary)

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

    private var quickSelections: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                selectionChip(tr("All", "ทั้งหมด"), selected: selectedFileIDs == nil) {
                    selectedFileIDs = nil
                }
                ForEach(DriveLinkAnalysis.FolderItem.Category.allCases, id: \.self) { category in
                    let categoryItems = items.filter { $0.category == category }
                    if !categoryItems.isEmpty {
                        selectionChip(categoryLabel(category), selected: selectedCategory(categoryItems)) {
                            selectedFileIDs = Set(categoryItems.map(\.id))
                        }
                    }
                }
            }
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
                ForEach(items) { item in listRow(item) }
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
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.dd(12, .semibold))
                    .foregroundStyle(selected ? DDTheme.accent : Color.white)
                    .shadow(color: .black.opacity(0.35), radius: 1)

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
            }
            .padding(5)
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
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
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

    private func selectionChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.dd(10, .medium))
            .buttonStyle(.plain)
            .foregroundStyle(selected ? DDTheme.accent : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(selected ? DDTheme.accentSoft : Color.secondary.opacity(0.08)))
    }

    private func selectAndFocus(_ item: DriveLinkAnalysis.FolderItem) {
        focusedItemID = item.id
        browserFocused = true
        var selected = selectedFileIDs ?? Set(items.map(\.id))
        if selected.contains(item.id) { selected.remove(item.id) }
        else { selected.insert(item.id) }
        selectedFileIDs = selected.count == items.count ? nil : selected
    }

    private func preview(_ item: DriveLinkAnalysis.FolderItem) {
        focusedItemID = item.id
        browserFocused = true
        withAnimation(.easeOut(duration: 0.14)) { previewedItem = item }
    }

    private func isSelected(_ id: String) -> Bool {
        selectedFileIDs?.contains(id) ?? true
    }

    private func selectedCategory(_ categoryItems: [DriveLinkAnalysis.FolderItem]) -> Bool {
        guard let selectedFileIDs else { return false }
        return selectedFileIDs == Set(categoryItems.map(\.id))
    }

    private func categoryLabel(_ category: DriveLinkAnalysis.FolderItem.Category) -> String {
        switch category {
        case .images: tr("Images", "รูป")
        case .videos: tr("Videos", "วิดีโอ")
        case .documents: tr("Docs", "เอกสาร")
        case .archives: tr("Archives", "ไฟล์บีบอัด")
        case .other: tr("Other", "อื่นๆ")
        }
    }

    private func itemAccessibilityLabel(_ item: DriveLinkAnalysis.FolderItem, selected: Bool) -> String {
        let state = selected ? tr("Selected", "เลือกแล้ว") : tr("Not selected", "ยังไม่เลือก")
        return "\(item.relativePath), \(state)"
    }
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

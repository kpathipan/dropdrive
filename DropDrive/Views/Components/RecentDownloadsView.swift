import SwiftUI
import UniformTypeIdentifiers

struct RecentDownloadsView: View {
    let items: [DownloadHistoryItem]
    @Binding var searchText: String
    let onRevealInFinder: (DownloadHistoryItem) -> Void
    let onCopyLink: (DownloadHistoryItem) -> Void
    let onClearHistory: () -> Void

    @AppStorage("recentGalleryMode") private var galleryMode = true
    /// When set, the gallery is drilled into this completed folder's contents.
    @State private var openedFolder: DownloadHistoryItem?

    private var filteredItems: [DownloadHistoryItem] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let openedFolder {
                FolderContentsGallery(item: openedFolder, onBack: { self.openedFolder = nil })
            } else {
                if items.count > 1 { searchField }

                // Filtered once and passed down — it used to be recomputed for
                // the emptiness check and again for whichever layout won.
                let visible = filteredItems
                if visible.isEmpty {
                    Text(tr("No matching downloads", "ไม่พบรายการที่ค้นหา"))
                        .font(.dd(11.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 14)
                        .cardBackground()
                } else if galleryMode {
                    gallery(visible)
                } else {
                    list(visible)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(tr("Recent Downloads", "ดาวน์โหลดล่าสุด"))
                .font(.dd(11, .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)

            Spacer()

            if openedFolder == nil {
                Button {
                    galleryMode.toggle()
                } label: {
                    Image(systemName: galleryMode ? "list.bullet" : "square.grid.2x2")
                        .font(.dd(12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(galleryMode ? tr("List view", "มุมมองรายการ") : tr("Gallery view", "มุมมองแกลเลอรี"))
                .accessibilityLabel(galleryMode ? "Switch to list view" : "Switch to gallery view")

                Button(tr("Clear History", "ล้างประวัติ"), action: onClearHistory)
                    .buttonStyle(.plain)
                    .font(.dd(11))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear download history")
            }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 120), spacing: 8)]

    private func gallery(_ visible: [DownloadHistoryItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(visible) { item in
                GalleryTile(
                    item: item,
                    onOpenFolder: { openedFolder = item },
                    onRevealInFinder: { onRevealInFinder(item) },
                    onCopyLink: { onCopyLink(item) }
                )
            }
        }
    }

    private func list(_ visible: [DownloadHistoryItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider().padding(.leading, 38)
                }
                RecentDownloadRow(item: item, onRevealInFinder: onRevealInFinder, onCopyLink: onCopyLink)
            }
        }
        .cardBackground()
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.dd(11))
                .foregroundStyle(.secondary)

            TextField(tr("Search downloads", "ค้นหาดาวน์โหลด"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.dd(12))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.dd(11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .cardBackground()
    }
}

// MARK: - Gallery tile

/// One item in the gallery: a real thumbnail for a file, a 2×2 cover collage for
/// a folder, or a type/status placeholder. Double-click opens (or drills into a
/// folder), Space previews via Quick Look, right-click has the full menu.
private struct GalleryTile: View {
    let item: DownloadHistoryItem
    let onOpenFolder: () -> Void
    let onRevealInFinder: () -> Void
    let onCopyLink: () -> Void

    @State private var isHovering = false
    @State private var statusCache = FileStatusCache.shared

    private var url: URL? { item.itemURL }
    /// Cached lookup — a tile's body must not touch the filesystem. Until the
    /// first check lands the tile renders as present, which is right the vast
    /// majority of the time and avoids a flash of "missing" on every open.
    private var status: FileStatusCache.Status? {
        url.flatMap { statusCache.status(for: $0) }
    }
    private var exists: Bool {
        guard url != nil else { return false }
        return status?.exists ?? true
    }
    private var isFolder: Bool {
        if let status, status.exists { return status.isDirectory }
        return (item.fileCount ?? 1) > 1
    }
    private var isAudio: Bool {
        ["mp3", "m4a", "aac", "wav", "flac"].contains(url?.pathExtension.lowercased() ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                cover
                if isHovering, exists {
                    Color.black.opacity(0.35)
                    HStack(spacing: 10) {
                        tileButton(isFolder ? "arrow.down.forward.square" : "eye", action: primaryAction)
                        tileButton("folder", action: onRevealInFinder)
                    }
                }
            }
            .frame(height: 62)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))

            Text(item.name)
                .font(.dd(9.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .foregroundStyle(exists ? .primary : .secondary)
        }
        .background(DDTheme.card)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DDTheme.border, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(exists ? 1 : 0.55)
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: primaryAction)
        .contextMenu {
            if exists {
                Button(isFolder ? tr("Open in DropDrive", "เปิดในแอพ") : tr("Open", "เปิด"), action: primaryAction)
                Button(tr("Quick Look", "ดูตัวอย่าง")) { if let url { QuickLookPresenter.shared.preview(url) } }
                Button(tr("Reveal in Finder", "เปิดใน Finder"), action: onRevealInFinder)
            }
            Button(tr("Copy Google Drive Link", "คัดลอกลิงก์ Google Drive"), action: onCopyLink)
        }
        .accessibilityElement()
        .accessibilityLabel(item.name)
    }

    private func primaryAction() {
        guard let url, exists else { return }
        if isFolder {
            onOpenFolder()
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func tileButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.dd(13, .medium))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.black.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cover: some View {
        if !exists {
            placeholder(icon: "questionmark.square.dashed", tint: .secondary, bg: DDTheme.rail)
        } else if isFolder, let url {
            FolderCover(folderURL: url, fileCount: item.fileCount)
        } else if isAudio {
            placeholder(icon: "music.note", tint: DDTheme.accent, bg: DDTheme.accentSoft)
        } else if let url {
            FileThumbnail(url: url)
        }
    }

    private func placeholder(icon: String, tint: Color, bg: Color) -> some View {
        ZStack {
            bg
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(tint)
        }
    }
}

/// A single file's Quick Look thumbnail, filling the tile. Falls back to the
/// system file-type icon until (or if) the thumbnail resolves.
private struct FileThumbnail: View {
    let url: URL
    @State private var model = ThumbnailModel()

    var body: some View {
        ZStack {
            DDTheme.rail
            if let image = model.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(nsImage: FileTypeIcon.forFile(at: url))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
            }
        }
        .onAppear { model.load(url: url, side: 120) }
    }
}

/// `NSWorkspace.icon(forFile:)` is a LaunchServices round trip, and the
/// placeholder that calls it sits in a tile body — so it ran for every visible
/// tile on every redraw until its thumbnail arrived. The icon only depends on
/// the file's type, so one lookup per extension covers the whole gallery.
@MainActor
private enum FileTypeIcon {
    private static var cache: [String: NSImage] = [:]

    static func forFile(at url: URL) -> NSImage {
        let key = url.pathExtension.lowercased()
        if let cached = cache[key] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[key] = icon
        return icon
    }
}

/// A 2×2 collage of the first few files inside a downloaded folder, with a count
/// badge — the folder's "album cover".
private struct FolderCover: View {
    let folderURL: URL
    let fileCount: Int?

    @State private var covers: [URL] = []

    var body: some View {
        ZStack {
            if covers.isEmpty {
                ZStack {
                    Color(red: 0.996, green: 0.953, blue: 0.780)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.09))
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)], spacing: 1) {
                    ForEach(0..<4, id: \.self) { i in
                        if i < covers.count {
                            FileThumbnail(url: covers[i])
                                .frame(height: 30)
                                .clipped()
                        } else {
                            DDTheme.rail.frame(height: 30)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let fileCount, fileCount > 0 {
                Text("\(fileCount)")
                    .font(.dd(9, .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.black.opacity(0.65)))
                    .padding(4)
            }
        }
        .overlay(alignment: .topLeading) {
            Image(systemName: "folder.fill")
                .font(.dd(9))
                .foregroundStyle(.white)
                .padding(3)
                .background(Circle().fill(.black.opacity(0.5)))
                .padding(4)
        }
        .task {
            covers = await Thumbnailer.shared.coverCandidates(in: folderURL)
        }
    }
}

// MARK: - Folder drill-in

/// The gallery drilled into one downloaded folder: a grid of the files inside,
/// each previewable (Space / double-click), with a back button.
private struct FolderContentsGallery: View {
    let item: DownloadHistoryItem
    let onBack: () -> Void

    @State private var files: [URL] = []
    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 120), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.dd(11, .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DDTheme.accent)
                .accessibilityLabel("Back to recent downloads")

                Text(item.name)
                    .font(.dd(11.5, .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(tr("\(files.count) files", "\(files.count) ไฟล์"))
                    .font(.dd(10.5))
                    .foregroundStyle(.secondary)
            }

            if files.isEmpty {
                Text(tr("This folder is empty or was moved.", "โฟลเดอร์นี้ว่างหรือถูกย้ายไปแล้ว"))
                    .font(.dd(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .cardBackground()
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(files.enumerated()), id: \.element) { index, url in
                        FileTile(url: url, allFiles: files, index: index)
                    }
                }
            }
        }
        .task {
            guard let folderURL = item.itemURL else { return }
            // Off the main actor: a folder with hundreds of files means as many
            // `resourceValues` calls, and this view appears mid-animation.
            files = await Thumbnailer.shared.files(in: folderURL)
        }
    }
}

/// A plain file tile inside the folder drill-in. Space/eye previews it in
/// context (the whole folder, starting here); double-click opens it.
private struct FileTile: View {
    let url: URL
    let allFiles: [URL]
    let index: Int

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                FileThumbnail(url: url)
                if isHovering {
                    Color.black.opacity(0.35)
                    HStack(spacing: 10) {
                        button("eye") { QuickLookPresenter.shared.preview(allFiles, startingAt: index) }
                        button("arrow.up.forward") { NSWorkspace.shared.open(url) }
                    }
                }
            }
            .frame(height: 62)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))

            Text(url.lastPathComponent)
                .font(.dd(9.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
        }
        .background(DDTheme.card)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DDTheme.border, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button(tr("Open", "เปิด")) { NSWorkspace.shared.open(url) }
            Button(tr("Quick Look", "ดูตัวอย่าง")) { QuickLookPresenter.shared.preview(allFiles, startingAt: index) }
            Button(tr("Reveal in Finder", "เปิดใน Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    private func button(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.dd(13, .medium))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.black.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - List row (unchanged fallback)

private struct RecentDownloadRow: View {
    let item: DownloadHistoryItem
    let onRevealInFinder: (DownloadHistoryItem) -> Void
    let onCopyLink: (DownloadHistoryItem) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 18)
                .accessibilityLabel(statusLabel)

            Text(item.name)
                .font(.dd(12.5))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            if item.itemURL != nil {
                Button {
                    onRevealInFinder(item)
                } label: {
                    Image(systemName: "folder")
                        .font(.dd(12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isHovering ? Color.accentColor : .secondary)
                .help("Reveal in Finder")
                .accessibilityLabel("Reveal in Finder")
            }

            Text(item.date, style: .time)
                .font(.dd(11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            if item.itemURL != nil {
                Button(tr("Reveal in Finder", "เปิดใน Finder")) { onRevealInFinder(item) }
            }
            Button(tr("Copy Google Drive Link", "คัดลอกลิงก์ Google Drive")) { onCopyLink(item) }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusIcon: String {
        switch item.status {
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .completed: .green
        case .failed: .orange
        case .cancelled: .secondary
        }
    }

    private var statusLabel: String {
        switch item.status {
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.dd(26))
                .foregroundStyle(.tertiary)

            Text(tr("Download Google Drive files and folders effortlessly.", "ดาวน์โหลดไฟล์และโฟลเดอร์จาก Google Drive ได้ง่ายๆ"))
                .font(.dd(12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

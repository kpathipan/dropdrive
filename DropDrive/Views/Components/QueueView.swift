import SwiftUI

struct QueueView: View {
    let queue: [QueueItem]
    let summary: QueueSummary
    let canStartQueue: Bool
    let isLargeDownload: Bool
    let showLargeDownloadWarning: Bool
    let activeProgress: DownloadProgress?
    let highlightedItemID: UUID?
    let canPauseQueue: Bool
    let canResumeQueue: Bool
    let onStartQueue: () -> Void
    let onConfirmLargeDownload: () -> Void
    let onCancelLargeDownload: () -> Void
    let onRemove: (UUID) -> Void
    let onRetry: (UUID) -> Void
    let onCancelActive: () -> Void
    let onPauseActive: () -> Void
    let onResumePaused: () -> Void
    let onRevealInFinder: (QueueItem) -> Void
    let onOpen: (QueueItem) -> Void
    let onClearCompleted: () -> Void
    let onPauseQueue: () -> Void
    let onResumeQueue: () -> Void
    let onReorder: (UUID, UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showLargeDownloadWarning {
                largeDownloadWarningCard
            } else if canStartQueue {
                summaryCard
            }

            ForEach(queue) { item in
                QueueRow(
                    item: item,
                    isHighlighted: item.id == highlightedItemID,
                    progress: item.status == .downloading ? activeProgress : nil,
                    onRemove: { onRemove(item.id) },
                    onRetry: { onRetry(item.id) },
                    onCancelActive: onCancelActive,
                    onPauseActive: onPauseActive,
                    onResumePaused: onResumePaused,
                    onRevealInFinder: { onRevealInFinder(item) },
                    onOpen: { onOpen(item) }
                )
                .id(item.id)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .applyingIf(item.status == .ready) { view in
                    view
                        .draggable(item.id.uuidString)
                        .dropDestination(for: String.self) { draggedIDs, _ in
                            guard let draggedIDString = draggedIDs.first, let draggedID = UUID(uuidString: draggedIDString) else { return false }
                            onReorder(draggedID, item.id)
                            return true
                        }
                }
            }

            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(footerSummary)
                .font(.dd(11))
                .foregroundStyle(.secondary)

            Spacer()

            if queue.contains(where: { $0.status == .completed }) {
                Button(tr("Clear done", "ล้างที่เสร็จ"), action: onClearCompleted)
                    .buttonStyle(.plain)
                    .font(.dd(11))
                    .foregroundStyle(DDTheme.accent)
                    .accessibilityLabel("Clear completed downloads from queue")
            }

            if canPauseQueue {
                Button(tr("Pause all", "หยุดทั้งหมด"), action: onPauseQueue)
                    .buttonStyle(.plain)
                    .font(.dd(11))
                    .foregroundStyle(DDTheme.accent)
                    .accessibilityLabel("Pause the download queue")
            } else if canResumeQueue {
                Button(tr("Resume all", "ทำต่อทั้งหมด"), action: onResumeQueue)
                    .buttonStyle(.plain)
                    .font(.dd(11))
                    .foregroundStyle(DDTheme.accent)
                    .accessibilityLabel("Resume the download queue")
            }
        }
        .padding(.horizontal, 2)
    }

    private var footerSummary: String {
        // One pass, not three: this is rebuilt on every progress tick.
        var downloading = 0
        var pending = 0
        var done = 0
        for item in queue {
            switch item.status {
            case .downloading, .paused: downloading += 1
            case .ready: pending += 1
            case .completed: done += 1
            case .failed, .cancelled: break
            }
        }
        var parts: [String] = []
        if downloading > 0 { parts.append(tr("\(downloading) downloading", "กำลังโหลด \(downloading)")) }
        if pending > 0 { parts.append(tr("\(pending) queued", "รอคิว \(pending)")) }
        if done > 0 { parts.append(tr("\(done) done", "เสร็จ \(done)")) }
        return parts.isEmpty ? tr("Queue empty", "คิวว่าง") : parts.joined(separator: " · ")
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 16) {
                    summaryDetail(tr("\(summary.linkCount) \(summary.linkCount == 1 ? "link" : "links")", "\(summary.linkCount) ลิงก์"), icon: "link")
                    summaryDetail(tr("\(summary.totalFiles) \(summary.totalFiles == 1 ? "file" : "files")", "\(summary.totalFiles) ไฟล์"), icon: "doc.on.doc")
                }
                HStack(spacing: 16) {
                    summaryDetail(Formatters.byteCount(summary.totalBytes), icon: "internaldrive")
                    if let seconds = summary.estimatedSeconds, let remaining = Formatters.remainingTime(seconds) {
                        summaryDetail(remaining, icon: "clock")
                    }
                }
            }
            .font(.dd(11))
            .foregroundStyle(.secondary)

            Button(action: onStartQueue) {
                Label(tr("Download All", "ดาวน์โหลดทั้งหมด"), systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStartQueue)
        }
        .padding(16)
        .cardBackground()
    }

    private func summaryDetail(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
    }

    private var largeDownloadWarningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.dd(18))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Large Download", "ดาวน์โหลดขนาดใหญ่"))
                        .font(.dd(13, .semibold))
                    Text(tr("This will download \(Formatters.byteCount(summary.totalBytes)).", "จะดาวน์โหลดทั้งหมด \(Formatters.byteCount(summary.totalBytes))"))
                        .font(.dd(11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                Button(tr("Cancel", "ยกเลิก"), role: .cancel, action: onCancelLargeDownload)
                    .buttonStyle(.bordered)

                Button(tr("Continue", "ดำเนินการต่อ"), action: onConfirmLargeDownload)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .cardBackground()
        .accessibilityElement(children: .contain)
    }
}

private struct QueueRow: View {
    let item: QueueItem
    let isHighlighted: Bool
    let progress: DownloadProgress?
    let onRemove: () -> Void
    let onRetry: () -> Void
    let onCancelActive: () -> Void
    let onPauseActive: () -> Void
    let onResumePaused: () -> Void
    let onRevealInFinder: () -> Void
    let onOpen: () -> Void

    @State private var isHovering = false
    @State private var showCompletionSweep = false
    @State private var statusCache = FileStatusCache.shared

    /// Whether the finished item is still where it was put. Read through the
    /// cache rather than `fileExists`: this row redraws with every progress
    /// update, and a synchronous stat per redraw is a stat several times a
    /// second per completed row.
    private var resultStillOnDisk: Bool {
        guard let url = item.resultURL else { return false }
        return statusCache.status(for: url)?.exists ?? true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                thumbnail

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.dd(13, .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 4) {
                        if let totalBytes = item.analysis.totalBytes {
                            Text(Formatters.byteCount(totalBytes))
                        }
                        if let fileCount = item.analysis.fileCount {
                            Text("· \(fileCount) \(fileCount == 1 ? "file" : "files")")
                        }
                    }
                    .font(.dd(11))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if item.status == .completed, resultStillOnDisk {
                    Button(tr("Open", "เปิด"), action: onOpen)
                        .buttonStyle(.plain)
                        .font(.dd(11, .medium))
                        .foregroundStyle(DDTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(DDTheme.accentSoft))
                        .help(tr("Open the downloaded item", "เปิดไฟล์ที่ดาวน์โหลด"))
                        .accessibilityLabel("Open \(item.displayName)")

                    Button(action: onRevealInFinder) {
                        Image(systemName: "folder")
                            .font(.dd(11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(tr("Reveal in Finder", "เปิดใน Finder"))
                    .accessibilityLabel("Reveal in Finder")
                }

                statusIndicator

                // Removing used to be right-click-only. A cancelled row still drew
                // an "xmark.circle.fill" status icon, which reads exactly like a
                // remove control and did nothing when clicked — so this is a real
                // button, and that status icon no longer impersonates one.
                if item.status != .downloading {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.dd(11, .bold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                    .help(tr("Remove from queue", "เอาออกจากคิว"))
                    .accessibilityLabel("Remove from queue")
                }
            }
            .accessibilityElement(children: .combine)

            if let breakdown = item.analysis.categoryBreakdown, !breakdown.isEmpty {
                categoryRow(breakdown)
            }

            if item.status == .downloading, let progress {
                inlineProgress(progress)
            }

            if item.status == .failed {
                HStack(alignment: .top, spacing: 8) {
                    if let errorMessage = item.errorMessage {
                        Text(errorMessage)
                            .font(.dd(11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer()
                    }

                    Button(tr("Retry", "ลองใหม่"), action: onRetry)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .cardBackground()
        // The gallery lifts under the pointer and the queue did not, which made
        // the two panes feel like different apps. Same easing, less travel — a
        // row is wide, and lifting it as far as a tile would look like a card
        // being dragged.
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.04 : 0))
                .allowsHitTesting(false)
        }
        // A finished row says so for a moment, rather than only changing its
        // badge: the sweep is what the eye catches when the window is open in
        // the corner of the screen and the tick is 13pt.
        .overlay {
            if showCompletionSweep {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [.green.opacity(0), .green.opacity(0.22), .green.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(DDTheme.accent.opacity(0.5), lineWidth: 1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isHighlighted)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onChange(of: item.status) { _, newStatus in
            guard newStatus == .completed else { return }
            withAnimation(.easeIn(duration: 0.2)) { showCompletionSweep = true }
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeOut(duration: 0.35)) { showCompletionSweep = false }
            }
        }
        .contextMenu {
            if item.status == .completed {
                Button(tr("Reveal in Finder", "เปิดใน Finder"), action: onRevealInFinder)
            }
            if item.status != .downloading {
                Button(tr("Remove", "ลบออก"), action: onRemove)
            }
        }
    }

    private func categoryRow(_ breakdown: DriveLinkAnalysis.CategoryBreakdown) -> some View {
        HStack(spacing: 12) {
            if breakdown.images > 0 { categoryChip("photo", breakdown.images, label: "images") }
            if breakdown.videos > 0 { categoryChip("video", breakdown.videos, label: "videos") }
            if breakdown.documents > 0 { categoryChip("doc.text", breakdown.documents, label: "documents") }
            if breakdown.archives > 0 { categoryChip("archivebox", breakdown.archives, label: "archives") }
            if breakdown.other > 0 { categoryChip("questionmark.folder", breakdown.other, label: "other files") }
        }
        .font(.dd(11))
        .foregroundStyle(.secondary)
        .padding(.leading, 32)
    }

    private func categoryChip(_ icon: String, _ count: Int, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text("\(count)")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(label)")
    }

    /// The download's own row carries the progress, filling left to right behind
    /// the text, instead of a separate bar underneath it.
    ///
    /// The bar was a third row of its own and said nothing the percentage beside
    /// the filename didn't already say precisely. The fill gives the same
    /// at-a-glance read in space that was already being used — and every number
    /// stays, because on a download manager the exact byte count, rate and ETA
    /// are the product, not decoration.
    private func inlineProgress(_ progress: DownloadProgress) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(progress.currentFileName.isEmpty ? tr("Downloading…", "กำลังดาวน์โหลด…") : progress.currentFileName)
                    .font(.dd(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if let fraction = progress.fractionCompleted {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.dd(11, .medium).monospacedDigit())
                        .foregroundStyle(DDTheme.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(DDTheme.accent.opacity(0.10))
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(DDTheme.accent.opacity(0.28))
                            .frame(width: proxy.size.width * (progress.fractionCompleted ?? 0))
                    }
                }
            }
            // Matches the sampling the engine reports at, so the fill glides
            // rather than stepping.
            .animation(.linear(duration: 0.25), value: progress.fractionCompleted)

            HStack(spacing: 4) {
                if progress.totalBytes > 0 {
                    Text(tr("\(Formatters.byteCount(progress.bytesDownloaded)) of \(Formatters.byteCount(progress.totalBytes))", "\(Formatters.byteCount(progress.bytesDownloaded)) จาก \(Formatters.byteCount(progress.totalBytes))"))
                }

                if progress.bytesPerSecond > 0 {
                    if progress.totalBytes > 0 { Text("·") }
                    Text(Formatters.transferSpeed(progress.bytesPerSecond))
                }

                if let etaSeconds = progress.etaSeconds, let remaining = Formatters.remainingTime(etaSeconds) {
                    Text("·")
                    Text(remaining)
                }

                Spacer()

                Button(tr("Pause", "หยุดพัก"), action: onPauseActive)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                Button(tr("Cancel", "ยกเลิก"), role: .cancel, action: onCancelActive)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
            .font(.dd(11))
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 32)
    }

    /// The picture the row leads with, in descending order of how much it tells
    /// you: the clip's own poster frame, the finished file's Quick Look preview,
    /// then the icon macOS uses for that file type, and only then a glyph.
    ///
    /// A column of identical blue play-triangles was the single least informative
    /// thing in the app — the queue is a list of the user's own footage, and it
    /// looked like a list of nothing in particular. A Drive file has no picture
    /// until it has finished downloading, so it gets its real type icon rather
    /// than a grey rectangle pretending a thumbnail is coming.
    @ViewBuilder
    private var thumbnail: some View {
        Group {
            // A completed folder has a URL too, but asking Quick Look for its
            // "file" thumbnail falls back to the generic blank-document icon.
            // Folders are the download result here, so keep their visual
            // identity explicit before considering file posters/thumbnails.
            if item.analysis.type == .folder {
                placeholder
            } else if let poster = item.analysis.thumbnailURL, let url = URL(string: poster) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        placeholder
                    }
                }
            } else if item.status == .completed, resultStillOnDisk, let url = item.resultURL {
                FileThumbnail(url: url)
            } else {
                placeholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DDTheme.border, lineWidth: 0.5)
        }
        // The green tick stays — it was the leading glyph before the picture
        // took that place, and it is how "this one is done" is read without
        // reading anything. It moves onto the corner of the thumbnail rather
        // than being dropped.
        .overlay(alignment: .bottomTrailing) {
            if item.status == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.dd(13))
                    .foregroundStyle(.white, .green)
                    .padding(2)
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        ZStack {
            DDTheme.rail
            if item.analysis.type == .folder {
                Image(systemName: "folder.fill")
                    .font(.dd(17))
                    .foregroundStyle(.secondary)
            } else {
                Image(nsImage: FileTypeIcon.forFile(at: URL(fileURLWithPath: item.displayName)))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 26, height: 26)
            }
        }
    }

    private var statusIndicator: some View {
        Group {
            switch item.status {
            case .ready:
                Text(tr("queued", "รอคิว"))
                    .font(.dd(11))
                    .foregroundStyle(.tertiary)
            case .downloading:
                ProgressView()
                    .controlSize(.small)
            case .completed:
                EmptyView()
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .cancelled:
                // Deliberately not an xmark: that's the remove button's glyph, and
                // sharing it made this look like a control that could be clicked.
                Image(systemName: "slash.circle")
                    .foregroundStyle(.secondary)
            case .paused:
                Button(tr("Resume", "โหลดต่อ"), action: onResumePaused)
                    .buttonStyle(.plain)
                    .font(.dd(11, .medium))
                    .foregroundStyle(DDTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(DDTheme.accentSoft))
            }
        }
        .font(.dd(13))
        .accessibilityLabel(statusLabel)
    }

    private var statusLabel: String {
        switch item.status {
        case .ready: "Ready"
        case .downloading: "Downloading"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .paused: "Paused"
        }
    }
}

private extension View {
    @ViewBuilder
    func applyingIf<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

import SwiftUI

/// Lightweight, local-only counters derived from Recent Downloads history — no
/// analytics, no telemetry, nothing leaves the device.
struct StatisticsSection: View {
    @State private var historyStore = DownloadHistoryStore.shared

    var body: some View {
        // Kept as a rollup on the store — recomputed when history changes, not
        // on every redraw of this pane.
        let totals = historyStore.totals
        let mix = Self.mix(of: historyStore.items)

        Section {
            statRow(tr("Total Downloads", "ดาวน์โหลดทั้งหมด"), value: "\(totals.completedCount)")
            statRow(tr("Total Files", "ไฟล์ทั้งหมด"), value: "\(totals.totalFiles)")
            statRow(tr("Total Downloaded", "ปริมาณที่ดาวน์โหลด"), value: Formatters.byteCount(totals.totalBytes))
        } header: {
            Text(tr("Statistics", "สถิติ"))
        }

        // Three numbers were the whole pane, and a number cannot answer the
        // question this pane is actually asked — "what do I pull down all day?"
        // The bar answers it at a glance, from history the app already keeps.
        if !mix.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    GeometryReader { proxy in
                        HStack(spacing: 2) {
                            ForEach(mix, id: \.kind) { slice in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(slice.kind.colour)
                                    .frame(width: max(3, proxy.size.width * slice.share))
                            }
                        }
                    }
                    .frame(height: 10)

                    // Wraps rather than scrolls: at 380pt wide three legend
                    // entries fit on a line and five categories is the maximum.
                    FlowLegend(slices: mix)
                }
                .padding(.vertical, 2)
            } header: {
                Text(tr("What you download", "ส่วนใหญ่โหลดอะไร"))
            }
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Mix

    enum Kind: String, CaseIterable {
        case videos, images, documents, archives, other

        var label: String {
            switch self {
            case .videos: tr("Videos", "วิดีโอ")
            case .images: tr("Images", "รูปภาพ")
            case .documents: tr("Documents", "เอกสาร")
            case .archives: tr("Archives", "ไฟล์บีบอัด")
            case .other: tr("Other", "อื่นๆ")
            }
        }

        var colour: Color {
            switch self {
            case .videos: DDTheme.accent
            case .images: .teal
            case .documents: .orange
            case .archives: .purple
            case .other: .gray
            }
        }
    }

    struct Slice {
        let kind: Kind
        let count: Int
        let share: Double
    }

    /// Categorised from the downloaded file's own name — the only thing history
    /// keeps that says what a file was. A folder counts once, as what it is,
    /// rather than as the files inside it, which history never recorded.
    static func mix(of items: [DownloadHistoryItem]) -> [Slice] {
        var counts: [Kind: Int] = [:]
        for item in items where item.status == .completed {
            counts[kind(for: item.name), default: 0] += 1
        }
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }
        return Kind.allCases.compactMap { kind in
            guard let count = counts[kind], count > 0 else { return nil }
            return Slice(kind: kind, count: count, share: Double(count) / Double(total))
        }
    }

    private static func kind(for name: String) -> Kind {
        switch (name as NSString).pathExtension.lowercased() {
        case "mp4", "mov", "m4v", "avi", "mkv", "webm", "mpg", "mpeg", "wmv":
            return .videos
        case "jpg", "jpeg", "png", "heic", "gif", "tiff", "tif", "webp", "raw", "dng", "bmp":
            return .images
        case "pdf", "doc", "docx", "rtf", "txt", "odt", "pages", "xls", "xlsx",
             "csv", "numbers", "ppt", "pptx", "key", "md":
            return .documents
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz":
            return .archives
        default:
            return .other
        }
    }
}

/// The bar's key. Laid out in rows of three so a Thai label, which runs longer
/// than its English counterpart, never pushes an entry off the edge.
private struct FlowLegend: View {
    let slices: [StatisticsSection.Slice]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(stride(from: 0, to: slices.count, by: 3)), id: \.self) { start in
                HStack(spacing: 12) {
                    ForEach(slices[start..<min(start + 3, slices.count)], id: \.kind) { slice in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(slice.kind.colour)
                                .frame(width: 7, height: 7)
                            Text("\(slice.kind.label) \(Int((slice.share * 100).rounded()))%")
                                .font(.dd(11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

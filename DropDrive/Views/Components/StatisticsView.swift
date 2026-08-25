import SwiftUI

/// Lightweight, local-only counters derived from Recent Downloads history — no
/// analytics, no telemetry, nothing leaves the device.
struct StatisticsSection: View {
    @State private var historyStore = DownloadHistoryStore.shared
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        // Kept as a rollup on the store — recomputed when history changes, not
        // on every redraw of this pane.
        let totals = historyStore.totals
        let mix = Self.mix(of: historyStore.items)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Statistics", "สถิติ"))
                        .font(.dd(17, .bold))
                    Text(tr("Stored only on this Mac", "เก็บข้อมูลไว้เฉพาะใน Mac เครื่องนี้"))
                        .font(.dd(10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chart.bar.xaxis")
                    .font(.dd(18, .semibold))
                    .foregroundStyle(DDTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(DDTheme.accentSoft))
            }

            LazyVGrid(columns: columns, spacing: 8) {
                metricCard(
                    tr("Downloads", "ดาวน์โหลด"),
                    value: "\(totals.completedCount)",
                    icon: "arrow.down.circle.fill"
                )
                metricCard(
                    tr("Files", "ไฟล์ทั้งหมด"),
                    value: "\(totals.totalFiles)",
                    icon: "doc.on.doc.fill"
                )
                metricCard(
                    tr("Downloaded", "ขนาดรวม"),
                    value: Formatters.byteCount(totals.totalBytes),
                    icon: "internaldrive.fill"
                )
            }

            if mix.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.dd(20))
                        .foregroundStyle(DDTheme.accent)
                    Text(tr(
                        "Your download mix will appear after the first completed item.",
                        "สัดส่วนประเภทไฟล์จะแสดงหลังดาวน์โหลดรายการแรกเสร็จ"
                    ))
                    .font(.dd(11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .cardBackground()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("What you download", "ส่วนใหญ่โหลดอะไร"))
                        .font(.dd(12, .semibold))

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
                .padding(14)
                .cardBackground()
            }
        }
    }

    private func metricCard(_ label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.dd(13, .semibold))
                .foregroundStyle(DDTheme.accent)

            Text(value)
                .font(.dd(17, .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(label)
                .font(.dd(10, .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(10)
        .cardBackground()
        .accessibilityElement(children: .combine)
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

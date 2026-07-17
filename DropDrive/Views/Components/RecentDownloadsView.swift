import SwiftUI

struct RecentDownloadsView: View {
    let items: [DownloadHistoryItem]
    @Binding var searchText: String
    let onRevealInFinder: (DownloadHistoryItem) -> Void
    let onCopyLink: (DownloadHistoryItem) -> Void
    let onClearHistory: () -> Void

    private var filteredItems: [DownloadHistoryItem] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("Recent Downloads", "ดาวน์โหลดล่าสุด"))
                    .font(.dd(11, .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)

                Spacer()

                Button(tr("Clear History", "ล้างประวัติ"), action: onClearHistory)
                    .buttonStyle(.plain)
                    .font(.dd(11))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear download history")
            }

            if items.count > 1 {
                searchField
            }

            if filteredItems.isEmpty {
                Text(tr("No matching downloads", "ไม่พบรายการที่ค้นหา"))
                    .font(.dd(11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
                    .cardBackground()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 38)
                        }
                        RecentDownloadRow(item: item, onRevealInFinder: onRevealInFinder, onCopyLink: onCopyLink)
                    }
                }
                .cardBackground()
            }
        }
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

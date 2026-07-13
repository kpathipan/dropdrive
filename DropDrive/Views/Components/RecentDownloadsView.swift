import SwiftUI

struct RecentDownloadsView: View {
    let items: [DownloadHistoryItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Downloads")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 38)
                    }
                    RecentDownloadRow(item: item)
                }
            }
            .cardBackground()
        }
    }
}

private struct RecentDownloadRow: View {
    let item: DownloadHistoryItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 18)
                .accessibilityLabel(statusLabel)

            Text(item.name)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            Text(item.date, style: .time)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)

            Text("Download Google Drive files and folders effortlessly.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

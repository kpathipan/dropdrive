import SwiftUI

/// Lightweight, local-only counters derived from Recent Downloads history — no
/// analytics, no telemetry, nothing leaves the device.
struct StatisticsSection: View {
    @State private var historyStore = DownloadHistoryStore.shared

    private var completedItems: [DownloadHistoryItem] {
        historyStore.items.filter { $0.status == .completed }
    }

    private var totalFiles: Int {
        completedItems.reduce(0) { $0 + ($1.fileCount ?? 1) }
    }

    private var totalBytes: Int64 {
        completedItems.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
    }

    var body: some View {
        Section {
            statRow("Total Downloads", value: "\(completedItems.count)")
            statRow("Total Files", value: "\(totalFiles)")
            statRow("Total Downloaded", value: Formatters.byteCount(totalBytes))
        } header: {
            Text("Statistics")
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
}

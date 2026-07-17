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
            statRow(tr("Total Downloads", "ดาวน์โหลดทั้งหมด"), value: "\(completedItems.count)")
            statRow(tr("Total Files", "ไฟล์ทั้งหมด"), value: "\(totalFiles)")
            statRow(tr("Total Downloaded", "ปริมาณที่ดาวน์โหลด"), value: Formatters.byteCount(totalBytes))
        } header: {
            Text(tr("Statistics", "สถิติ"))
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

import SwiftUI

/// Lightweight, local-only counters derived from Recent Downloads history — no
/// analytics, no telemetry, nothing leaves the device.
struct StatisticsSection: View {
    @State private var historyStore = DownloadHistoryStore.shared

    var body: some View {
        // Kept as a rollup on the store — recomputed when history changes, not
        // on every redraw of this pane.
        let totals = historyStore.totals
        Section {
            statRow(tr("Total Downloads", "ดาวน์โหลดทั้งหมด"), value: "\(totals.completedCount)")
            statRow(tr("Total Files", "ไฟล์ทั้งหมด"), value: "\(totals.totalFiles)")
            statRow(tr("Total Downloaded", "ปริมาณที่ดาวน์โหลด"), value: Formatters.byteCount(totals.totalBytes))
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

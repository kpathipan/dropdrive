import SwiftUI

struct DownloadPanelView: View {
    let progress: DownloadProgress
    let onCancel: () -> Void

    private var fraction: Double? { progress.fractionCompleted }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(progress.currentFileName.isEmpty ? "Downloading…" : progress.currentFileName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.opacity)

                Spacer(minLength: 12)

                if let fraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
            }

            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(Color.accentColor)
                .animation(.easeInOut(duration: 0.2), value: fraction)

            HStack {
                if progress.totalBytes > 0 {
                    Text("\(Formatters.byteCount(progress.bytesDownloaded)) of \(Formatters.byteCount(progress.totalBytes))")
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

                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .cardBackground()
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

import SwiftUI

struct DownloadProgressView: View {
    let progress: DownloadProgress
    let onCancel: () -> Void

    private var fraction: Double? { progress.fractionCompleted }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Downloading…")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                if let fraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }

            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(Color.accentColor)
                .animation(.easeInOut(duration: 0.2), value: fraction)

            Text(progress.currentFileName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.opacity)

            if progress.totalBytes > 0 {
                Text("\(Formatters.byteCount(progress.bytesDownloaded)) of \(Formatters.byteCount(progress.totalBytes))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 14) {
                if progress.bytesPerSecond > 0 {
                    Label(Formatters.transferSpeed(progress.bytesPerSecond), systemImage: "gauge.with.dots.needle.67percent")
                }

                if let etaSeconds = progress.etaSeconds, let remaining = Formatters.remainingTime(etaSeconds) {
                    Label(remaining, systemImage: "clock")
                }

                Spacer()

                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
        .padding(16)
        .cardBackground()
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

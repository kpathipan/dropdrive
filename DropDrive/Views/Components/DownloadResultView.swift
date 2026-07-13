import SwiftUI

struct DownloadSuccessView: View {
    let folderURL: URL
    let fileCount: Int
    let onOpenInFinder: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 4) {
                Text("Download Complete")
                    .font(.system(size: 16, weight: .semibold))

                Text(fileCount == 1 ? "1 file saved to \(folderURL.lastPathComponent)" : "\(fileCount) files saved to \(folderURL.lastPathComponent)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button("Open in Finder", action: onOpenInFinder)
                    .buttonStyle(.bordered)

                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .cardBackground()
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

struct DownloadErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 4) {
                Text("Download Failed")
                    .font(.system(size: 16, weight: .semibold))

                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }

            HStack(spacing: 10) {
                Button("Cancel", role: .cancel, action: onDismiss)
                    .buttonStyle(.bordered)

                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .cardBackground()
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

struct DownloadCancelledView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            Text("Download Cancelled")
                .font(.system(size: 16, weight: .semibold))

            Button("Dismiss", action: onDismiss)
                .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .cardBackground()
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

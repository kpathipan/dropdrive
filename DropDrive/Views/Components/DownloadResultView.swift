import SwiftUI

struct DownloadSuccessView: View {
    let itemURL: URL
    let isFolder: Bool
    let fileCount: Int
    let onOpenInFinder: () -> Void
    let onDone: () -> Void

    private var completionMessage: String {
        guard isFolder else {
            return "File saved to \(itemURL.deletingLastPathComponent().lastPathComponent)"
        }
        return fileCount == 1 ? "1 file saved to \(itemURL.lastPathComponent)" : "\(fileCount) files saved to \(itemURL.lastPathComponent)"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 4) {
                Text("Download Complete")
                    .font(.system(size: 16, weight: .semibold))

                Text(completionMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 14) {
                Button("Download Another", action: onDone)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Button("Open Folder", action: onOpenInFinder)
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

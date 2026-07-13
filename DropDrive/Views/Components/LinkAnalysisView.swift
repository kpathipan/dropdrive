import SwiftUI

struct LinkAnalyzingView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("Analyzing link…")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground()
        .transition(.opacity)
    }
}

struct LinkNeedsConnectionView: View {
    let isSigningIn: Bool
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)

            Text("Sign in to Google Drive to access this item.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(isSigningIn ? "Connecting…" : "Connect", action: onConnect)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSigningIn)
        }
        .padding(14)
        .cardBackground()
        .transition(.opacity)
    }
}

struct LinkAnalysisErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(14)
        .cardBackground()
        .transition(.opacity)
    }
}

struct LinkAnalysisResultView: View {
    let analysis: DriveLinkAnalysis
    let canDownload: Bool
    let onDownload: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: analysis.type == .folder ? "folder.fill" : "doc.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(analysis.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(analysis.type == .folder ? "Folder" : "File")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                visibilityBadge
            }

            Divider()

            HStack(spacing: 16) {
                if let totalBytes = analysis.totalBytes {
                    detail(Formatters.byteCount(totalBytes), icon: "internaldrive")
                } else {
                    detail("Size unknown", icon: "internaldrive")
                }

                if let fileCount = analysis.fileCount {
                    detail("\(fileCount) \(fileCount == 1 ? "file" : "files")", icon: "doc.on.doc")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)

                Button(action: onDownload) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canDownload)
            }
        }
        .padding(16)
        .cardBackground()
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func detail(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
    }

    private var visibilityBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: analysis.isPublic ? "globe" : "lock.fill")
            Text(analysis.isPublic ? "Public" : "Private")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.6), in: Capsule())
    }
}

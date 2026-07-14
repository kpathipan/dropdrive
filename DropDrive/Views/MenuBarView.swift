import SwiftUI

struct MenuBarView: View {
    @State private var viewModel = DropDriveViewModel.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private static let mainWindowID = "main"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DropDrive")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                    if viewModel.isQueueProcessing {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text("Downloading")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if !viewModel.queue.isEmpty {
                        Text("\(viewModel.queue.count) in queue")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Ready")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: { NSApp.terminate(nil) }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Quit DropDrive")
                .accessibilityLabel("Quit DropDrive")
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Active Download Progress
            if let activeID = viewModel.activeQueueItemID,
               let activeItem = viewModel.queue.first(where: { $0.id == activeID }),
               let progress = viewModel.activeProgress {
                VStack(alignment: .leading, spacing: 8) {
                    Text(activeItem.analysis.name)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundColor(.primary)

                    ProgressView(value: progress.fractionCompleted)
                        .frame(height: 4)

                    HStack(spacing: 4) {
                        Text(progress.progressDescription)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        if let eta = progress.estimatedTimeRemaining {
                            Text(eta)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        if viewModel.isQueuePaused {
                            Button(action: viewModel.resumeQueue) {
                                Label("Resume", systemImage: "play.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button(action: viewModel.pauseQueue) {
                                Label("Pause", systemImage: "pause.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }

                        Button(action: viewModel.cancelActiveDownload) {
                            Label("Cancel", systemImage: "xmark")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)

                        Spacer()
                    }
                }
                .padding(12)

                Divider()
            }

            // Queue Items
            if !viewModel.queue.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.queue) { item in
                            QueueItemRowView(
                                item: item,
                                isActive: item.id == viewModel.activeQueueItemID,
                                onRemove: { viewModel.removeQueueItem(item.id) },
                                onReveal: {
                                    guard let url = item.resultURL else { return }
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                },
                                onRetry: { viewModel.retryQueueItem(item.id) }
                            )
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 200)

                Divider()
            }

            // Action Buttons
            HStack(spacing: 8) {
                Button(action: openMainWindow) {
                    Label("Open Window", systemImage: "arrow.up.left")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }) {
                    Image(systemName: "gear")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .help("Preferences…")
                .accessibilityLabel("Preferences")
            }
            .padding(12)
        }
        .frame(width: 320, alignment: .topLeading)
        .task {
            viewModel.restoreLogin()
        }
    }

    /// Focuses the existing main window if one is already open, rather than asking
    /// WindowGroup for another instance — `openWindow(id:)` always creates a new
    /// window, it doesn't refocus an existing one.
    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // Activating the app alone brings its existing window(s) forward; only ask
        // WindowGroup for a new one if none are open at all.
        guard viewModel.openMainWindowCount == 0 else { return }
        openWindow(id: Self.mainWindowID)
    }
}

struct QueueItemRowView: View {
    let item: QueueItem
    let isActive: Bool
    let onRemove: () -> Void
    let onReveal: () -> Void
    let onRetry: () -> Void

    var statusColor: Color {
        switch item.status {
        case .ready:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .downloading:
            return .orange
        case .cancelled:
            return .gray
        case .paused:
            return .yellow
        }
    }

    var statusIcon: String {
        switch item.status {
        case .ready:
            return "hourglass"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        case .downloading:
            return "arrow.down.circle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        case .paused:
            return "pause.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .font(.caption)
                .foregroundColor(statusColor)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.analysis.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(isActive ? .accentColor : .primary)
                Text(item.status.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                if item.status == .completed {
                    Button(action: onReveal) {
                        Image(systemName: "folder")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
                    .accessibilityLabel("Reveal in Finder")
                }

                if item.status == .failed {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .help("Retry")
                    .accessibilityLabel("Retry")
                }

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove")
                .accessibilityLabel("Remove")
            }
        }
        .padding(6)
        .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
}

// MARK: - Preview

#Preview {
    MenuBarView()
}

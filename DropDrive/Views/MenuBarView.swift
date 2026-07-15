import SwiftUI

struct MenuBarView: View {
    @State private var viewModel = DropDriveViewModel.shared
    @State private var historyStore = DownloadHistoryStore.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private static let mainWindowID = "main"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            pasteField
                .padding(12)

            Divider()

            statusLine
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            actions
                .padding(12)
        }
        .frame(width: 300, alignment: .topLeading)
        .task {
            viewModel.restoreLogin()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                Text("Drop").foregroundStyle(.primary)
                Text("Drive").foregroundStyle(Color(red: 0.145, green: 0.388, blue: 0.922))
            }
            .font(.system(size: 15, weight: .bold, design: .rounded))

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Quit DropDrive")
            .accessibilityLabel("Quit DropDrive")
        }
        .padding(12)
    }

    // MARK: - Paste field

    private var pasteField: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Paste a Drive link…", text: $viewModel.driveLink)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .disabled(viewModel.isSigningIn)
                .onSubmit(submitAndOpen)
                .accessibilityLabel("Google Drive link")

            Button(action: submitAndOpen) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.driveLink.isEmpty ? Color.secondary : Color.accentColor)
            .disabled(viewModel.driveLink.isEmpty || viewModel.isSigningIn)
            .help("Download")
            .accessibilityLabel("Download")
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Status line

    @ViewBuilder
    private var statusLine: some View {
        if let activeID = viewModel.activeQueueItemID,
           let activeItem = viewModel.queue.first(where: { $0.id == activeID }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                    Text(activeItem.analysis.name)
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    if let pct = viewModel.activeProgress?.fractionCompleted {
                        Text("\(Int(pct * 100))%")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: viewModel.activeProgress?.fractionCompleted ?? 0)
                    .frame(height: 3)

                HStack(spacing: 8) {
                    if viewModel.isQueuePaused {
                        Button("Resume", action: viewModel.resumeQueue)
                    } else {
                        Button("Pause", action: viewModel.pauseQueue)
                    }
                    Button("Cancel", action: viewModel.cancelActiveDownload)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .font(.system(size: 11))
                .buttonStyle(.borderless)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: idleIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(idleColor)
                Text(idleText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var completedToday: Int {
        let cal = Calendar.current
        return historyStore.items.filter {
            $0.status == .completed && cal.isDateInToday($0.date)
        }.count
    }

    private var idleIcon: String {
        if viewModel.queue.contains(where: { $0.status == .failed }) { return "exclamationmark.triangle.fill" }
        if completedToday > 0 { return "checkmark.circle.fill" }
        return "tray"
    }

    private var idleColor: Color {
        if viewModel.queue.contains(where: { $0.status == .failed }) { return .orange }
        if completedToday > 0 { return .green }
        return .secondary
    }

    private var idleText: String {
        if viewModel.queue.contains(where: { $0.status == .failed }) {
            return "A download failed — open to retry"
        }
        let n = completedToday
        if n > 0 {
            return "\(n) download\(n == 1 ? "" : "s") today, all done"
        }
        return "Ready"
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: openMainWindow) {
                Label("Open DropDrive", systemImage: "arrow.up.left")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .help("Preferences…")
            .accessibilityLabel("Preferences")
        }
    }

    // MARK: - Behaviour

    /// Submits the pasted link into the analysis pipeline, then brings the main
    /// window forward so the user can watch the queue — the menu bar deliberately
    /// doesn't show the full queue, so the window is where the work is visible.
    private func submitAndOpen() {
        guard !viewModel.driveLink.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        viewModel.handleSubmit()
        openMainWindow()
    }

    /// Focuses the existing main window if one is already open, rather than asking
    /// WindowGroup for another instance — `openWindow(id:)` always creates a new
    /// window, it doesn't refocus an existing one.
    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        guard viewModel.openMainWindowCount == 0 else { return }
        openWindow(id: Self.mainWindowID)
    }
}

// MARK: - Preview

#Preview {
    MenuBarView()
}

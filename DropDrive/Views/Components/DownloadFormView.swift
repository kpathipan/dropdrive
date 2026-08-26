import SwiftUI
import AppKit

struct DownloadFormView: View {
    @Binding var driveLink: String
    let destinationURL: URL?
    let isLocked: Bool
    /// True while an analysed card is on screen. That card carries its own
    /// destination row and its own Download button, so showing them here as
    /// well means the same two decisions appear twice on one small window —
    /// which is both confusing and a waste of two rows in a popover that has
    /// to fit under 480pt.
    let hasActiveCard: Bool
    let onChooseDestination: () -> Void
    let onSelectDestination: (URL) -> Void
    let onSubmit: () -> Void
    let onEscape: () -> Void
    @FocusState private var isLinkFieldFocused: Bool
    @State private var clipboardHasSupportedLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: DDMetrics.controlGap) {
            HStack {
                Label(tr("New download", "ดาวน์โหลดใหม่"), systemImage: "plus.circle.fill")
                    .font(.dd(11, .semibold))
                    .foregroundStyle(DDTheme.accent)

                Spacer()

                Text("⌘V")
                    .font(.dd(11, .medium).monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(DDTheme.rail))
            }

            HStack(spacing: DDMetrics.controlGap) {
                HStack(spacing: 7) {
                    Image(systemName: "link")
                        .font(.dd(13))
                        .foregroundStyle(.secondary)

                    TextField(tr("Drive / TikTok / YouTube / IG link…", "วางลิงก์ Drive / TikTok / YouTube / IG…"), text: $driveLink)
                        .textFieldStyle(.plain)
                        .font(.dd(13))
                        .focused($isLinkFieldFocused)
                        .disabled(isLocked)
                        .onSubmit(onSubmit)
                        .onExitCommand(perform: onEscape)
                        .accessibilityLabel("Google Drive link")

                    if driveLink.isEmpty, clipboardHasSupportedLink {
                        Button(action: pasteFromClipboard) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.dd(11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(isLocked)
                        .accessibilityLabel("Paste")
                    } else {
                        Button(action: { driveLink = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.dd(11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(isLocked)
                        .accessibilityLabel("Clear")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: DDMetrics.controlHeight)
                .inputFieldBackground()

                if !hasActiveCard {
                    Button(action: onSubmit) {
                        Label(tr("Analyze", "วิเคราะห์"), systemImage: "arrow.right")
                            .font(.dd(11, .semibold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 78, minHeight: DDMetrics.controlHeight, maxHeight: DDMetrics.controlHeight)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(driveLink.isEmpty || isLocked ? DDTheme.accent.opacity(0.4) : DDTheme.accent)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(driveLink.isEmpty || isLocked)
                    .help(tr("Analyze link", "วิเคราะห์ลิงก์"))
                    .accessibilityLabel("Analyze link")
                }
            }

            if !hasActiveCard {
                DestinationRow(
                    destinationURL: destinationURL,
                    isLocked: isLocked,
                    showsLabel: true,
                    sourceLink: driveLink,
                    onChooseDestination: onChooseDestination,
                    onSelectDestination: onSelectDestination
                )

                Text(tr(
                    "Drive, YouTube, TikTok, Facebook, Instagram · paste multiple links",
                    "Drive, YouTube, TikTok, Facebook, Instagram · วางหลายลิงก์ได้"
                ))
                .font(.dd(11))
                .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .cardBackground()
        .onAppear {
            refreshClipboardSuggestion()
            guard !hasActiveCard, !isLocked else { return }
            isLinkFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshClipboardSuggestion()
        }
    }

    private func pasteFromClipboard() {
        let links = ClipboardLinkReader.links()
        guard !links.isEmpty else {
            clipboardHasSupportedLink = false
            return
        }
        driveLink = links.joined(separator: "\n")
        clipboardHasSupportedLink = false
    }

    /// Reading the clipboard is local-only. The button is intentionally offered
    /// only when it contains a link DropDrive can recognise, rather than showing
    /// a generic paste affordance for every copied private note or password.
    private func refreshClipboardSuggestion() {
        clipboardHasSupportedLink = !ClipboardLinkReader.links().isEmpty
    }
}

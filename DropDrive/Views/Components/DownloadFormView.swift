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
    let onSubmit: () -> Void
    let onEscape: () -> Void
    @FocusState private var isLinkFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
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

                    if driveLink.isEmpty {
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
                .frame(height: 34)
                .inputFieldBackground()

                if !hasActiveCard {
                    Button(action: onSubmit) {
                        Image(systemName: "arrow.down")
                            .font(.dd(14, .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(driveLink.isEmpty || isLocked ? DDTheme.accent.opacity(0.4) : DDTheme.accent)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(driveLink.isEmpty || isLocked)
                    .help(tr("Download", "ดาวน์โหลด"))
                    .accessibilityLabel("Download")
                }
            }

            if !hasActiveCard {
                destinationRow

                Text(tr(
                    "Supports Google Drive, YouTube, TikTok, Facebook, and Instagram.",
                    "รองรับ Google Drive, YouTube, TikTok, Facebook และ Instagram"
                ))
                .font(.dd(10))
                .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            guard !hasActiveCard, !isLocked else { return }
            isLinkFieldFocused = true
        }
    }

    private var destinationRow: some View {
        HStack(spacing: 5) {
            Text(tr("Save to", "บันทึกที่"))
                .font(.dd(10, .medium))
                .foregroundStyle(.tertiary)

            Image(systemName: destinationURL == nil ? "folder" : "folder.fill")
                .font(.dd(11))
                .foregroundStyle(destinationURL == nil ? Color.secondary : DDTheme.accent)

            // The folder's own name, not the whole path: at 10.5pt a full path
            // crowded the button beside it down to "เปลี่ยน…" with the label
            // clipped, and the leading directories were never the part anyone
            // was reading.
            Text(destinationURL?.lastPathComponent ?? tr("Choose a folder", "เลือกโฟลเดอร์"))
                .font(.dd(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1)
                .help(destinationURL?.path(percentEncoded: false) ?? "")

            Button(destinationURL == nil ? tr("Choose…", "เลือก…") : tr("Change…", "เปลี่ยน…"),
                   action: onChooseDestination)
                .buttonStyle(.plain)
                .font(.dd(11))
                .foregroundStyle(DDTheme.accent)
                .disabled(isLocked)
                .fixedSize()
                .accessibilityLabel(destinationURL == nil ? "Choose destination folder" : "Change destination folder")

            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
    }

    private func pasteFromClipboard() {
        if let text = NSPasteboard.general.string(forType: .string) {
            driveLink = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

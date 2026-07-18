import SwiftUI
import AppKit

struct DownloadFormView: View {
    @Binding var driveLink: String
    let destinationURL: URL?
    let isLocked: Bool
    let onChooseDestination: () -> Void
    let onSubmit: () -> Void
    let onEscape: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: "link")
                        .font(.dd(12))
                        .foregroundStyle(.secondary)

                    TextField(tr("Drive / TikTok / YouTube / IG link…", "วางลิงก์ Drive / TikTok / YouTube / IG…"), text: $driveLink)
                        .textFieldStyle(.plain)
                        .font(.dd(12.5))
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

                Button(action: onSubmit) {
                    Image(systemName: "arrow.down")
                        .font(.dd(14, .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(driveLink.isEmpty || isLocked ? DDTheme.accent.opacity(0.4) : DDTheme.accent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(driveLink.isEmpty || isLocked)
                .help("Download")
                .accessibilityLabel("Download")
            }

            HStack(spacing: 5) {
                Image(systemName: destinationURL == nil ? "folder" : "folder.fill")
                    .font(.dd(10))
                    .foregroundStyle(destinationURL == nil ? Color.secondary : DDTheme.accent)

                Text(destinationURL?.path(percentEncoded: false) ?? tr("Choose a folder", "เลือกโฟลเดอร์"))
                    .font(.dd(10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button(destinationURL == nil ? tr("Choose…", "เลือก…") : tr("Change…", "เปลี่ยน…"), action: onChooseDestination)
                    .buttonStyle(.plain)
                    .font(.dd(10.5))
                    .foregroundStyle(DDTheme.accent)
                    .disabled(isLocked)
                    .accessibilityLabel(destinationURL == nil ? "Choose destination folder" : "Change destination folder")

                Spacer(minLength: 0)
            }
            .padding(.leading, 2)
        }
    }

    private func pasteFromClipboard() {
        if let text = NSPasteboard.general.string(forType: .string) {
            driveLink = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

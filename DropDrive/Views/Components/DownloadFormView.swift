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
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Paste Google Drive link")

                HStack(spacing: 8) {
                    TextField("https://drive.google.com/...", text: $driveLink)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .disabled(isLocked)
                        .onSubmit(onSubmit)
                        .onExitCommand(perform: onEscape)
                        .accessibilityLabel("Google Drive link")

                    if driveLink.isEmpty {
                        Button(action: pasteFromClipboard) {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(isLocked)
                        .accessibilityLabel("Paste")
                    } else {
                        Button(action: { driveLink = "" }) {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(isLocked)
                        .accessibilityLabel("Clear")
                    }
                }
                .padding(8)
                .inputFieldBackground()
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Save to")

                HStack(spacing: 10) {
                    Image(systemName: destinationURL == nil ? "folder" : "folder.fill")
                        .foregroundStyle(destinationURL == nil ? .secondary : Color.accentColor)
                        .frame(width: 16)

                    Text(destinationURL?.path(percentEncoded: false) ?? "Choose a folder")
                        .font(.system(size: 13))
                        .foregroundStyle(destinationURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 12)

                    Button(destinationURL == nil ? "Choose…" : "Change…", action: onChooseDestination)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isLocked)
                        .accessibilityLabel(destinationURL == nil ? "Choose destination folder" : "Change destination folder")
                }
                .padding(8)
                .inputFieldBackground()
            }
        }
    }

    private func pasteFromClipboard() {
        if let text = NSPasteboard.general.string(forType: .string) {
            driveLink = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.4)
    }
}

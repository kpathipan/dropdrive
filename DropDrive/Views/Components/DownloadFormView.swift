import SwiftUI

struct DownloadFormView: View {
    @Binding var driveLink: String
    let destinationURL: URL?
    let isLocked: Bool
    let onChooseDestination: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Paste Google Drive link")

                TextField("https://drive.google.com/...", text: $driveLink)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(11)
                    .inputFieldBackground()
                    .disabled(isLocked)
            }

            VStack(alignment: .leading, spacing: 8) {
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

                    Button("Choose…", action: onChooseDestination)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isLocked)
                }
                .padding(11)
                .inputFieldBackground()
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.4)
    }
}

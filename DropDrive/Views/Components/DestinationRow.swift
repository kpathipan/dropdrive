import SwiftUI

/// One compact destination control, shared by the initial paste state and the
/// review card. It makes the eventual folder visible at the decision point and
/// exposes recent/favorite folders without turning the popover into a form.
struct DestinationRow: View {
    let destinationURL: URL?
    let isLocked: Bool
    let showsLabel: Bool
    let sourceLink: String?
    var category: DriveLinkAnalysis.FolderItem.Category? = nil
    let onChooseDestination: () -> Void
    let onSelectDestination: (URL) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if showsLabel {
                Text(tr("Save to", "บันทึกที่"))
                    .font(.dd(11, .medium))
                    .foregroundStyle(.secondary)
            }

            Image(systemName: destinationURL == nil ? "folder" : "folder.fill")
                .font(.dd(12))
                .foregroundStyle(destinationURL == nil ? .secondary : DDTheme.accent)

            Text(destinationURL?.lastPathComponent ?? tr("Choose a folder", "เลือกโฟลเดอร์"))
                .font(.dd(12))
                .foregroundStyle(destinationURL == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1)
                .help(destinationURL?.path(percentEncoded: false) ?? "")

            Spacer(minLength: 0)

            Menu {
                Button(tr("Choose folder…", "เลือกโฟลเดอร์…"), action: onChooseDestination)

                let favorites = DestinationStore.favorites()
                if !favorites.isEmpty {
                    Section(tr("Favorites", "โฟลเดอร์โปรด")) {
                        ForEach(favorites, id: \.standardizedFileURL) { url in
                            Button(url.lastPathComponent) { onSelectDestination(url) }
                        }
                    }
                }

                let recent = DestinationStore.recent().filter { candidate in
                    candidate.standardizedFileURL != destinationURL?.standardizedFileURL
                }
                if !recent.isEmpty {
                    Section(tr("Recent folders", "โฟลเดอร์ล่าสุด")) {
                        ForEach(recent, id: \.standardizedFileURL) { url in
                            Button(url.lastPathComponent) { onSelectDestination(url) }
                        }
                    }
                }

                if let destinationURL {
                    Divider()
                    Button(
                        DestinationStore.isFavorite(destinationURL)
                            ? tr("Remove favorite", "เอาออกจากโฟลเดอร์โปรด")
                            : tr("Add to favorites", "เพิ่มเป็นโฟลเดอร์โปรด")
                    ) {
                        DestinationStore.toggleFavorite(destinationURL)
                    }

                    if let sourceLink, let source = DestinationStore.sourceLabel(forLink: sourceLink) {
                        if DestinationStore.destinationRule(forLink: sourceLink) != nil {
                            Button(tr("Stop using this folder for \(source)", "เลิกใช้โฟลเดอร์นี้สำหรับ \(source)")) {
                                DestinationStore.removeDestinationRule(forLink: sourceLink)
                            }
                        } else {
                            Button(tr("Use this folder for \(source)", "ใช้โฟลเดอร์นี้สำหรับ \(source)")) {
                                DestinationStore.setDestinationRule(destinationURL, forLink: sourceLink)
                            }
                        }
                    }

                    if let category {
                        let label = DestinationStore.categoryLabel(category)
                        if DestinationStore.destinationRule(forCategory: category) != nil {
                            Button(tr("Stop using this folder for \(label)", "เลิกใช้โฟลเดอร์นี้สำหรับ\(label)")) {
                                DestinationStore.removeDestinationRule(forCategory: category)
                            }
                        } else {
                            Button(tr("Use this folder for \(label)", "ใช้โฟลเดอร์นี้สำหรับ\(label)")) {
                                DestinationStore.setDestinationRule(destinationURL, forCategory: category)
                            }
                        }
                    }
                }
            } label: {
                Text(destinationURL == nil ? tr("Choose", "เลือก") : tr("Change", "เปลี่ยน"))
                    .font(.dd(11, .medium))
                    .foregroundStyle(DDTheme.accent)
                    .frame(minHeight: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(isLocked)
            .accessibilityLabel(destinationURL == nil ? "Choose destination folder" : "Change destination folder")
        }
    }
}

import SwiftUI

struct PreferencesView: View {
    @State private var preferences = PreferencesStore.shared
    private let folderSelectionService: FolderSelectionServicing = FolderSelectionService()

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(preferences.defaultDownloadFolderURL?.path(percentEncoded: false) ?? "None")
                        .foregroundStyle(preferences.defaultDownloadFolderURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("Choose…") { chooseDefaultFolder() }

                    if preferences.defaultDownloadFolderURL != nil {
                        Button("Reset") { preferences.setDefaultDownloadFolder(nil) }
                    }
                }
            } header: {
                Text("Default Download Folder")
            }

            Section {
                Toggle("Open Finder when a download completes", isOn: $preferences.openFinderWhenComplete)
                Toggle("Play a sound when a download completes", isOn: $preferences.playNotificationSound)
                Toggle("Launch DropDrive at login", isOn: $preferences.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            preferences.syncLaunchAtLoginWithSystemState()
        }
    }

    private func chooseDefaultFolder() {
        Task {
            guard let url = await folderSelectionService.chooseDestinationFolder() else { return }
            preferences.setDefaultDownloadFolder(url)
        }
    }
}

#Preview {
    PreferencesView()
}

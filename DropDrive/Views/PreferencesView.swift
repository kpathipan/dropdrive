import SwiftUI

private enum BandwidthPreset: Hashable {
    case unlimited
    case megabytesPerSecond(Int)
    case custom

    static let presets: [BandwidthPreset] = [.unlimited, .megabytesPerSecond(5), .megabytesPerSecond(10), .megabytesPerSecond(20), .custom]

    var label: String {
        switch self {
        case .unlimited: "Unlimited"
        case .megabytesPerSecond(let value): "\(value) MB/s"
        case .custom: "Custom"
        }
    }

    var bytesPerSecond: Double? {
        switch self {
        case .unlimited, .custom: nil
        case .megabytesPerSecond(let value): Double(value) * 1_048_576
        }
    }

    static func matching(_ bytesPerSecond: Double?) -> BandwidthPreset {
        guard let bytesPerSecond else { return .unlimited }
        return presets.first { $0.bytesPerSecond == bytesPerSecond } ?? .custom
    }
}

struct PreferencesView: View {
    @State private var preferences = PreferencesStore.shared
    @State private var customLimitMBps: Double = 1
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

            Section {
                Picker("Limit download speed", selection: bandwidthPresetBinding) {
                    ForEach(BandwidthPreset.presets, id: \.self) { preset in
                        Text(preset.label).tag(preset)
                    }
                }

                if bandwidthPresetBinding.wrappedValue == .custom {
                    HStack {
                        TextField("Speed limit", value: $customLimitMBps, format: .number)
                            .labelsHidden()
                            .onChange(of: customLimitMBps) { _, newValue in
                                preferences.bandwidthLimitBytesPerSecond = max(0.1, newValue) * 1_048_576
                            }
                        Text("MB/s")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Bandwidth")
            }

            Section {
                LabeledContent("Version", value: appVersion)
            } header: {
                Text("About")
            } footer: {
                Text("Download Google Drive files and folders directly to your Mac.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task {
            preferences.syncLaunchAtLoginWithSystemState()
            if BandwidthPreset.matching(preferences.bandwidthLimitBytesPerSecond) == .custom,
               let stored = preferences.bandwidthLimitBytesPerSecond {
                customLimitMBps = stored / 1_048_576
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var bandwidthPresetBinding: Binding<BandwidthPreset> {
        Binding(
            get: { BandwidthPreset.matching(preferences.bandwidthLimitBytesPerSecond) },
            set: { newValue in
                switch newValue {
                case .custom:
                    preferences.bandwidthLimitBytesPerSecond = max(0.1, customLimitMBps) * 1_048_576
                default:
                    preferences.bandwidthLimitBytesPerSecond = newValue.bytesPerSecond
                }
            }
        )
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

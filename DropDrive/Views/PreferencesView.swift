import SwiftUI

private enum BandwidthPreset: Hashable {
    case unlimited
    case megabytesPerSecond(Int)
    case custom

    static let presets: [BandwidthPreset] = [.unlimited, .megabytesPerSecond(5), .megabytesPerSecond(10), .megabytesPerSecond(20), .custom]

    var label: String {
        switch self {
        case .unlimited: tr("Unlimited", "ไม่จำกัด")
        case .megabytesPerSecond(let value): "\(value) MB/s"
        case .custom: tr("Custom", "กำหนดเอง")
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
    @State private var language = AppLanguage.shared
    @State private var theme = AppTheme.shared
    @State private var phoneInbox = PhoneInboxService.shared
    @State private var updates = UpdateService.shared
    @State private var customLimitMBps: Double = 1
    @State private var showingReleaseNotes = false
    private let folderSelectionService: FolderSelectionServicing = FolderSelectionService()

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(preferences.defaultDownloadFolderURL?.path(percentEncoded: false) ?? tr("None", "ยังไม่ได้ตั้ง"))
                        .foregroundStyle(preferences.defaultDownloadFolderURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button(tr("Choose…", "เลือก…")) { chooseDefaultFolder() }

                    if preferences.defaultDownloadFolderURL != nil {
                        Button(tr("Reset", "ล้างค่า")) { preferences.setDefaultDownloadFolder(nil) }
                    }
                }
            } header: {
                Text(tr("Default Download Folder", "โฟลเดอร์ดาวน์โหลดเริ่มต้น"))
            }

            Section {
                Toggle(tr("Receive links from your phone (iCloud)", "รับลิงก์จากมือถือ (iCloud)"), isOn: $phoneInbox.isEnabled)
            } footer: {
                Text(tr(
                    "An iOS Shortcut saves shared links into the DropDrive folder in iCloud Drive; the Mac queues them automatically.",
                    "คำสั่งลัดบนไอโฟนจะเซฟลิงก์ลงโฟลเดอร์ DropDrive ใน iCloud Drive แล้ว Mac ดึงเข้าคิวให้เอง"
                ))
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle(tr("Open Finder when a download completes", "เปิด Finder เมื่อดาวน์โหลดเสร็จ"), isOn: $preferences.openFinderWhenComplete)
                Toggle(tr("Play a sound when a download completes", "เล่นเสียงเมื่อดาวน์โหลดเสร็จ"), isOn: $preferences.playNotificationSound)
                Toggle(tr("Launch DropDrive at login", "เปิด DropDrive อัตโนมัติตอนเข้าเครื่อง"), isOn: $preferences.launchAtLogin)
            }

            Section {
                Toggle(
                    tr("Keep videos playable on Mac (H.264/MP4)", "ให้วิดีโอเปิดได้บน Mac (H.264/MP4)"),
                    isOn: $preferences.preferCompatibleVideo
                )
            } header: {
                Text(tr("Video", "วิดีโอ"))
            } footer: {
                Text(tr(
                    "On means files always open in QuickTime and editing software, capped at 1080p on videos whose higher resolutions are AV1 only. Off takes the best available, up to 4K.",
                    "เปิดไว้ = ไฟล์เปิดได้ใน QuickTime และโปรแกรมตัดต่อเสมอ แต่บางคลิปจะได้สูงสุด 1080p (เพราะ 4K มีเฉพาะ AV1) ปิด = เอาคุณภาพสูงสุดถึง 4K"
                ))
                .foregroundStyle(.secondary)
            }

            Section {
                Picker(tr("Limit download speed", "จำกัดความเร็วดาวน์โหลด"), selection: bandwidthPresetBinding) {
                    ForEach(BandwidthPreset.presets, id: \.self) { preset in
                        Text(preset.label).tag(preset)
                    }
                }

                if bandwidthPresetBinding.wrappedValue == .custom {
                    HStack {
                        TextField(tr("Speed limit", "ความเร็วสูงสุด"), value: $customLimitMBps, format: .number)
                            .labelsHidden()
                            .onChange(of: customLimitMBps) { _, newValue in
                                preferences.bandwidthLimitBytesPerSecond = max(0.1, newValue) * 1_048_576
                            }
                        Text("MB/s")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(tr("Bandwidth", "แบนด์วิดท์"))
            }

            Section {
                Picker(tr("Language", "ภาษา"), selection: $language.code) {
                    Text("English").tag(AppLanguage.english)
                    Text("ไทย").tag(AppLanguage.thai)
                }
                .pickerStyle(.segmented)
            } header: {
                Text(tr("Language", "ภาษา"))
            }

            Section {
                Picker(tr("Theme", "ธีม"), selection: $theme.mode) {
                    Text(tr("System", "ตามอุปกรณ์")).tag(AppTheme.system)
                    Text(tr("Light", "สว่าง")).tag(AppTheme.light)
                    Text(tr("Dark", "มืด")).tag(AppTheme.dark)
                }
                .pickerStyle(.segmented)
            } header: {
                Text(tr("Theme", "ธีม"))
            }

            Section {
                LabeledContent(tr("Version", "เวอร์ชัน"), value: appVersion)
                if updates.isConfigured {
                    updateRow
                }
            } header: {
                Text(tr("About", "เกี่ยวกับ"))
            } footer: {
                Text(tr("Download Google Drive files and folders directly to your Mac.", "ดาวน์โหลดไฟล์และโฟลเดอร์จาก Google Drive ลงเครื่อง Mac ของคุณโดยตรง"))
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

    /// The update control, which is the whole update UI: one row that reflects
    /// whatever the service is doing — idle, checking, offering, downloading.
    @ViewBuilder
    private var updateRow: some View {
        switch updates.state {
        case .checking:
            LabeledContent(tr("Updates", "อัปเดต")) {
                Text(tr("Checking…", "กำลังตรวจสอบ…")).foregroundStyle(.secondary)
            }
        case .upToDate:
            LabeledContent(tr("Updates", "อัปเดต")) {
                HStack(spacing: 6) {
                    Text(tr("Up to date", "เป็นเวอร์ชันล่าสุดแล้ว")).foregroundStyle(.secondary)
                    Button(tr("Check again", "ตรวจอีกครั้ง")) { updates.checkNow() }
                }
            }
        case .available(let release):
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Version \(release.version) is available", "มีเวอร์ชัน \(release.version)"))
                    .font(.dd(12.5, .medium))
                Text(Formatters.byteCount(release.sizeBytes))
                    .font(.dd(10.5))
                    .foregroundStyle(.secondary)
                ReleaseNotesDisclosure(notes: release.fullNotes, isExpanded: $showingReleaseNotes)
                Button(tr("Update and relaunch", "อัปเดตและเปิดใหม่")) { updates.installUpdate() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 2)
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Downloading the update…", "กำลังดาวน์โหลดอัปเดต…")).font(.dd(12))
                ProgressView(value: progress.fraction)
                UpdateProgressDetail(progress: progress)
            }
        case .installing:
            LabeledContent(tr("Updates", "อัปเดต")) {
                Text(tr("Installing — DropDrive will reopen…", "กำลังติดตั้ง — แอพจะเปิดใหม่เอง…"))
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.dd(11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("Try again", "ลองใหม่")) { updates.checkNow() }
            }
        case .idle:
            LabeledContent(tr("Updates", "อัปเดต")) {
                Button(tr("Check for updates", "ตรวจหาอัปเดต")) { updates.checkNow() }
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

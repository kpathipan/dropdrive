import SwiftUI

private enum SettingsTab: Hashable {
    case general, transfers, appearance, about
}

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
    @State private var historyStore = DownloadHistoryStore.shared
    @State private var viewModel = DropDriveViewModel.shared
    @State private var selectedTab: SettingsTab = .general
    private let folderSelectionService: FolderSelectionServicing = FolderSelectionService()

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label(tr("General", "ทั่วไป"), systemImage: "gearshape") }
                .tag(SettingsTab.general)

            transferTab
                .tabItem { Label(tr("Downloads", "ดาวน์โหลด"), systemImage: "arrow.down.circle") }
                .tag(SettingsTab.transfers)

            appearanceTab
                .tabItem { Label(tr("Appearance", "หน้าตา"), systemImage: "paintbrush") }
                .tag(SettingsTab.appearance)

            aboutTab
                .tabItem { Label(tr("About", "เกี่ยวกับ"), systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .padding(.top, 8)
        .monospacedDigit()
        .task {
            preferences.syncLaunchAtLoginWithSystemState()
            if BandwidthPreset.matching(preferences.bandwidthLimitBytesPerSecond) == .custom,
               let stored = preferences.bandwidthLimitBytesPerSecond {
                customLimitMBps = stored / 1_048_576
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dropDriveShowAttention)) { _ in
            selectedTab = .transfers
        }
    }

    private var generalTab: some View {
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
                Toggle(isOn: $phoneInbox.isEnabled) {
                    Label(tr("Receive links from your phone (iCloud)", "รับลิงก์จากมือถือ (iCloud)"), systemImage: "iphone")
                }
            } footer: {
                Text(tr(
                    "An iOS Shortcut saves shared links into the DropDrive folder in iCloud Drive; the Mac queues them automatically.",
                    "คำสั่งลัดบนไอโฟนจะเซฟลิงก์ลงโฟลเดอร์ DropDrive ใน iCloud Drive แล้ว Mac ดึงเข้าคิวให้เอง"
                ))
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $preferences.openFinderWhenComplete) {
                    Label(tr("Open Finder when a download completes", "เปิด Finder เมื่อดาวน์โหลดเสร็จ"), systemImage: "folder")
                }
                Toggle(isOn: $preferences.playNotificationSound) {
                    Label(tr("Play a sound when a download completes", "เล่นเสียงเมื่อดาวน์โหลดเสร็จ"), systemImage: "speaker.wave.2")
                }
                Toggle(isOn: $preferences.launchAtLogin) {
                    Label(tr("Launch DropDrive at login", "เปิด DropDrive อัตโนมัติตอนเข้าเครื่อง"), systemImage: "power")
                }
            }

            Section {
                LabeledContent {
                    Text(GlobalShortcutService.displayName)
                        .font(.dd(12, .medium).monospaced())
                        .foregroundStyle(.secondary)
                } label: {
                    Label(tr("Open DropDrive", "เปิด DropDrive"), systemImage: "keyboard")
                }
            } header: {
                Text(tr("Keyboard Shortcut", "คีย์ลัด"))
            } footer: {
                Text(tr(
                    "Works from any app and prepares supported links currently on the clipboard.",
                    "ใช้ได้จากทุกแอป และเตรียมลิงก์ที่รองรับจากคลิปบอร์ดให้พร้อมวิเคราะห์"
                ))
                .foregroundStyle(.secondary)
            }
        }
        .settingsFormStyle()
    }

    private var transferTab: some View {
        Form {
            Section {
                Picker(selection: bandwidthPresetBinding) {
                    ForEach(BandwidthPreset.presets, id: \.self) { preset in
                        Text(preset.label).tag(preset)
                    }
                } label: {
                    Label(tr("Limit download speed", "จำกัดความเร็วดาวน์โหลด"), systemImage: "speedometer")
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
                Toggle(isOn: $preferences.preferCompatibleVideo) {
                    Label(tr("Keep videos playable on Mac (H.264/MP4)", "ให้วิดีโอเปิดได้บน Mac (H.264/MP4)"), systemImage: "play.rectangle")
                }
                Toggle(isOn: $preferences.showMenuBarProgress) {
                    Label(tr("Show live progress in the menu bar", "แสดงความคืบหน้าบนเมนูบาร์"), systemImage: "menubar.rectangle")
                }
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
                if viewModel.attentionItems.isEmpty {
                    Label(tr("Everything is ready", "ทุกอย่างพร้อมใช้งาน"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DDTheme.success)
                } else {
                    ForEach(viewModel.attentionItems) { item in
                        attentionRow(item)
                    }
                }
            } header: {
                HStack {
                    Text(tr("Needs Attention", "ต้องตรวจสอบ"))
                    if !viewModel.attentionItems.isEmpty {
                        Text("\(viewModel.attentionItems.count)")
                            .font(.dd(9, .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.orange))
                    }
                }
            } footer: {
                Text(tr(
                    "Connection drops retry automatically. Disconnected drives continue as soon as they return.",
                    "เน็ตหลุดจะลองใหม่อัตโนมัติ และงานจะทำต่อทันทีเมื่อไดรฟ์กลับมา"
                ))
                .foregroundStyle(.secondary)
            }
        }
        .settingsFormStyle()
    }

    private func attentionRow(_ item: QueueItem) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: item.attentionKind == .destination
                  ? "externaldrive.badge.exclamationmark"
                  : "wifi.exclamationmark")
                .foregroundStyle(.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.dd(11, .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(attentionMessage(for: item))
                    .font(.dd(10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if item.attentionKind == .network || item.status == .failed {
                        Button(tr("Retry now", "ลองใหม่ตอนนี้")) { viewModel.retryQueueItem(item.id) }
                            .controlSize(.small)
                    }
                    if item.attentionKind == .destination {
                        Button(tr("Change destination", "เปลี่ยนปลายทาง")) { viewModel.changeDestination(for: item.id) }
                            .controlSize(.small)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 3)
    }

    private func attentionMessage(for item: QueueItem) -> String {
        if item.attentionKind == .destination {
            return tr(
                "Waiting for the drive to reconnect. It will continue automatically.",
                "กำลังรอไดรฟ์เชื่อมต่อกลับมา แล้วจะทำต่ออัตโนมัติ"
            )
        }
        if item.attentionKind == .network, let date = item.nextRetryAt {
            return tr(
                "Connection lost. Retrying at \(date.formatted(date: .omitted, time: .shortened)).",
                "เน็ตหลุด จะลองใหม่เวลา \(date.formatted(date: .omitted, time: .shortened))"
            )
        }
        return item.errorMessage ?? tr("Retry this download.", "ลองดาวน์โหลดรายการนี้อีกครั้ง")
    }

    private var appearanceTab: some View {
        Form {
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
        }
        .settingsFormStyle()
    }

    private var aboutTab: some View {
        Form {
            Section {
                let totals = historyStore.totals
                LabeledContent(tr("Downloads", "ดาวน์โหลด"), value: "\(totals.completedCount)")
                LabeledContent(tr("Files", "ไฟล์ทั้งหมด"), value: "\(totals.totalFiles)")
                LabeledContent(tr("Downloaded", "ขนาดรวม"), value: Formatters.byteCount(totals.totalBytes))
            } header: {
                Text(tr("Local statistics", "สถิติในเครื่อง"))
            } footer: {
                Text(tr("Stored only on this Mac.", "เก็บเฉพาะใน Mac เครื่องนี้"))
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(tr("Version", "เวอร์ชัน"), value: appVersion)
                if updates.isConfigured {
                    updateRow
                }
            } header: {
                Text(tr("About", "เกี่ยวกับ"))
            } footer: {
                Text(tr(
                    "A private, native download queue for Drive and video links. No analytics or telemetry.",
                    "คิวดาวน์โหลดแบบเนทีฟสำหรับลิงก์ Drive และวิดีโอ ไม่มี analytics หรือ telemetry"
                ))
                    .foregroundStyle(.secondary)
            }
        }
        .settingsFormStyle()
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
                    .font(.dd(13, .medium))
                Text(Formatters.byteCount(release.sizeBytes))
                    .font(.dd(11))
                    .foregroundStyle(.secondary)
                ReleaseNotesDisclosure(notes: release.fullNotes, isExpanded: $showingReleaseNotes)
                Button(tr("Update and relaunch", "อัปเดตและเปิดใหม่")) { updates.installUpdate() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 2)
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Downloading the update…", "กำลังดาวน์โหลดอัปเดต…")).font(.dd(13))
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

private extension View {
    func settingsFormStyle() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
    }
}

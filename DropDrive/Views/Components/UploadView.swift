import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Compact in-popover upload surface. Every action feeds UploadCoordinator,
/// exactly like the private MCP command channel.
struct UploadView: View {
    @State private var uploads = UploadCoordinator.shared
    @State private var model = DropDriveViewModel.shared
    @State private var isDropTargeted = false
    @State private var newFolderName = "DropDrive Uploads"
    @State private var rename: [UUID: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("Upload to Google Drive", "อัปโหลดไป Google Drive")).font(.headline)
                if let error = uploads.storageError {
                    Text(error).foregroundStyle(.red)
                } else {
                    accountControls
                    if uploads.hasUploadPermission {
                        destinationControls
                        fileControls
                    } else {
                        Text(tr("Enable uploads once for this account. Google credentials stay in DropDrive.", "เปิดสิทธิ์อัปโหลดให้บัญชีนี้ครั้งเดียว ข้อมูลล็อกอินอยู่ใน DropDrive"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let message = uploads.message {
                        Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    }
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(uploads.jobs, id: \.command.id) { job in jobRow(job) }
                    }
                }
            }
            .padding(14)
        }
        .background(isDropTargeted ? DDTheme.accentSoft : .clear)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    Task { @MainActor in uploads.selectFiles([url]) }
                }
            }
            return !providers.isEmpty
        }
        .task { await uploads.checkPermission() }
    }

    private var accountControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.googleAccounts.isEmpty {
                Picker(tr("Account", "บัญชี"), selection: $uploads.selectedAccountID) {
                    ForEach(model.googleAccounts) { account in
                        Text(account.email).tag(Optional(account.userID))
                    }
                }
                .disabled(uploads.isAuthorizing || uploads.isLoadingFolders || uploads.isCreatingFolder)
                .onChange(of: uploads.selectedAccountID) { _, account in
                    if uploads.selectedFolder?.accountID != account { uploads.selectedFolder = nil }
                    uploads.folders = []; uploads.nextFolderPage = nil
                    Task { await uploads.checkPermission() }
                }
            }
            if !uploads.hasUploadPermission {
                Button {
                    Task { await uploads.authorize() }
                } label: {
                    Label(uploads.isAuthorizing ? tr("Waiting for Google…", "รออนุญาตจาก Google…") : tr("Enable uploads", "เปิดสิทธิ์อัปโหลด"), systemImage: "person.crop.circle.badge.checkmark")
                }.disabled(uploads.isAuthorizing)
            }
        }
    }

    private var destinationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Drive destination", "โฟลเดอร์ปลายทางใน Drive")).font(.subheadline.weight(.medium))
            HStack {
                TextField(tr("Folder link or ID", "ลิงก์หรือ ID โฟลเดอร์"), text: $uploads.folderInput)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: uploads.folderInput) { _, value in
                        if value != uploads.selectedFolder?.id { uploads.selectedFolder = nil }
                    }
                    .onSubmit { Task { await uploads.useFolder(uploads.folderInput) } }
                Button(tr("Use", "เลือก")) { Task { await uploads.useFolder(uploads.folderInput) } }
                    .disabled(uploads.folderInput.isEmpty || uploads.isLoadingFolders)
            }
            HStack {
                Button(tr("Browse folders", "เลือกจากโฟลเดอร์")) { Task { await uploads.browseFolders() } }
                Button(tr("My Drive", "ไดรฟ์ของฉัน")) { Task { await uploads.useFolder("root") } }
                if uploads.isLoadingFolders { ProgressView().controlSize(.small) }
            }
            if let folder = uploads.selectedFolder {
                Label(folder.path, systemImage: folder.driveID == nil ? "folder.fill" : "externaldrive.fill")
                    .font(.caption).foregroundStyle(DDTheme.accent).textSelection(.enabled)
                Text(folder.id).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if !uploads.folders.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(uploads.folders) { folder in
                            Button { Task { await uploads.useFolder(folder.id) } } label: {
                                Label(folder.name, systemImage: folder.driveID == nil ? "folder" : "externaldrive")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.disabled(!folder.canUpload)
                        }
                        if uploads.nextFolderPage != nil {
                            Button(tr("More folders", "ดูเพิ่ม")) { Task { await uploads.browseFolders(more: true) } }
                        }
                    }
                }.frame(maxHeight: 120)
            }
            HStack {
                TextField(tr("New folder name", "ชื่อโฟลเดอร์ใหม่"), text: $newFolderName).textFieldStyle(.roundedBorder)
                Button(tr("Create", "สร้าง")) { Task { await uploads.createDestination(named: newFolderName) } }
                    .disabled(uploads.isCreatingFolder || newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text(uploads.selectedFolder == nil ? tr("New folder will be created in My Drive.", "โฟลเดอร์ใหม่จะอยู่ในไดรฟ์ของฉัน") : tr("New folder will be created inside the selected destination.", "โฟลเดอร์ใหม่จะอยู่ภายในปลายทางที่เลือก"))
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(10).background(DDTheme.rail, in: RoundedRectangle(cornerRadius: 10))
    }

    private var fileControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: uploads.chooseFiles) { Label(tr("Choose files or drop here", "เลือกไฟล์ หรือลากไฟล์มาวาง"), systemImage: "plus.circle") }
            ForEach(uploads.selectedFiles, id: \.path) { url in
                HStack {
                    Image(systemName: "doc")
                    TextField(url.lastPathComponent, text: Binding(get: { uploads.selectedNames[url.path] ?? url.lastPathComponent }, set: { uploads.selectedNames[url.path] = $0 }))
                        .textFieldStyle(.roundedBorder)
                    Button { uploads.selectedFiles.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle") }
                        .help(tr("Remove selection", "เอาออกจากรายการ"))
                }
            }
            Button { uploads.startSelectedFiles() } label: { Label(tr("Upload \(uploads.selectedFiles.count) files", "อัปโหลด \(uploads.selectedFiles.count) ไฟล์"), systemImage: "arrow.up.circle.fill") }
                .buttonStyle(.borderedProminent)
                .disabled(uploads.selectedFiles.isEmpty || uploads.selectedFolder == nil)
        }.padding(10).background(DDTheme.rail, in: RoundedRectangle(cornerRadius: 10))
    }

    private func jobRow(_ job: AutomationJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(job.name ?? "Upload").font(.subheadline.weight(.medium)).lineLimit(2)
            Text(stateLabel(job.state)).font(.caption).foregroundStyle(job.state == "completed" ? .green : .secondary)
            if let status = job.upload, status.totalBytes > 0 {
                ProgressView(value: Double(status.bytesUploaded), total: Double(status.totalBytes))
                Text("\(Formatters.byteCount(status.bytesUploaded)) / \(Formatters.byteCount(status.totalBytes))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let message = job.message { Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if job.errorCode == "name_conflict" {
                TextField(tr("New filename", "เปลี่ยนชื่อไฟล์"), text: Binding(get: { rename[job.command.id] ?? job.name ?? "" }, set: { rename[job.command.id] = $0 }))
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                if ["failed", "cancelled", "interrupted"].contains(job.state) {
                    Button(tr("Retry", "ลองใหม่")) {
                        do { _ = try uploads.retry(job.command.id, newName: rename[job.command.id]) }
                        catch { uploads.message = (error as? AutomationFailure)?.message ?? "Cannot retry this job." }
                    }
                }
                if !job.terminal && job.state != "cancelling" {
                    Button(tr("Cancel", "ยกเลิก")) { _ = try? uploads.cancel(job.command.id) }
                }
                if let link = job.upload?.remoteURL, let url = URL(string: link) {
                    Link(tr("Open in Drive", "เปิดใน Drive"), destination: url)
                }
            }.font(.caption)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(DDTheme.rail, in: RoundedRectangle(cornerRadius: 10))
    }

    private func stateLabel(_ state: String) -> String {
        switch state {
        case "queued": tr("Queued", "อยู่ในคิว")
        case "hashing": tr("Checking source", "ตรวจไฟล์ต้นทาง")
        case "preparing": tr("Preparing", "เตรียมอัปโหลด")
        case "uploading": tr("Uploading", "กำลังอัปโหลด")
        case "verifying": tr("Verifying on Drive", "ตรวจยืนยันไฟล์บน Drive")
        case "completed": tr("Uploaded and verified", "อัปโหลดและตรวจยืนยันแล้ว")
        case "retrying": tr("Waiting to retry", "รอลองใหม่อัตโนมัติ")
        case "interrupted": tr("Ready to resume", "รออัปโหลดต่อ")
        case "cancelling": tr("Stopping safely", "กำลังหยุด")
        case "cancelled": tr("Cancelled", "ยกเลิกแล้ว")
        default: tr("Upload failed", "อัปโหลดไม่สำเร็จ")
        }
    }
}

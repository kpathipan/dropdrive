import SwiftUI

struct LinkAnalyzingView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text(tr("Analyzing link…", "กำลังวิเคราะห์ลิงก์…"))
                .font(.dd(13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground()
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
}

struct LinkInvalidView: View {
    let link: String
    let onClear: () -> Void

    private var message: String {
        let host = URL(string: link)?.host?.lowercased() ?? ""
        if host == "photos.google.com" || host.hasSuffix(".photos.google.com") {
            return tr(
                "Google Photos albums aren't supported yet. Paste a Google Drive, YouTube, TikTok, Facebook, or Instagram link instead.",
                "อัลบั้ม Google Photos ยังไม่รองรับ — ลองวางลิงก์ Google Drive, YouTube, TikTok, Facebook หรือ Instagram แทน"
            )
        }
        return tr(
            "Paste a Google Drive, YouTube, TikTok, Facebook, or Instagram link.",
            "วางลิงก์ Google Drive, YouTube, TikTok, Facebook หรือ Instagram"
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.dd(13))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(tr("Clear", "ล้าง"), action: onClear)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(16)
        .cardBackground()
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
}

struct LinkNeedsConnectionView: View {
    let isSigningIn: Bool
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)

            Text(tr("Sign in to Google Drive to access this item.", "ลงชื่อเข้า Google Drive เพื่อเข้าถึงรายการนี้"))
                .font(.dd(13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(isSigningIn ? tr("Connecting…", "กำลังเชื่อมต่อ…") : tr("Connect", "เชื่อมต่อ"), action: onConnect)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSigningIn)
                .accessibilityLabel("Connect Google Drive")
        }
        .padding(16)
        .cardBackground()
        .transition(.opacity)
    }
}

struct LinkDuplicateActiveView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.secondary)

            Text(tr("Already in queue.", "อยู่ในคิวแล้ว"))
                .font(.dd(13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .cardBackground()
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
}

struct LinkAnalysisErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.dd(13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(tr("Retry", "ลองใหม่"), action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(16)
        .cardBackground()
        .transition(.opacity)
    }
}

/// A pasted collection gets one deliberate review step. A single inaccessible
/// link should never block its neighbours, and nothing starts until the user
/// explicitly adds the selected rows to the queue.
struct BatchReviewView: View {
    let items: [BatchLinkReview]
    let destinationURL: URL?
    let onChooseDestination: () -> Void
    let onSelectDestination: (URL) -> Void
    let onToggle: (String) -> Void
    let onAdd: () -> Void
    let onCancel: () -> Void

    private var selectedCount: Int {
        items.filter { item in
            if case .ready = item.result { return item.isSelected }
            return false
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Review links", "ตรวจสอบลิงก์"))
                        .font(.dd(13, .semibold))
                    Text(tr("Choose what to add — downloads will not start yet.", "เลือกรายการที่จะเข้าคิว — ยังไม่เริ่มดาวน์โหลด"))
                        .font(.dd(11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(items.count)")
                    .font(.dd(12, .semibold).monospacedDigit())
                    .foregroundStyle(DDTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(DDTheme.accentSoft))
            }

            DestinationRow(
                destinationURL: destinationURL,
                isLocked: false,
                showsLabel: true,
                sourceLink: nil,
                onChooseDestination: onChooseDestination,
                onSelectDestination: onSelectDestination
            )

            ForEach(items) { item in
                batchRow(item)
            }

            HStack(spacing: 10) {
                Button(tr("Cancel", "ยกเลิก"), role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)

                Button(action: onAdd) {
                    Label(
                        tr("Add \(selectedCount) to queue", "เพิ่ม \(selectedCount) เข้าคิว"),
                        systemImage: "plus.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCount == 0 || destinationURL == nil)
            }
        }
        .padding(16)
        .cardBackground()
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private func batchRow(_ item: BatchLinkReview) -> some View {
        switch item.result {
        case .ready(let analysis):
            Button { onToggle(item.link) } label: {
                HStack(spacing: 9) {
                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isSelected ? DDTheme.accent : Color.secondary)
                    Image(systemName: analysis.isVideo == true ? "play.rectangle.fill" : analysis.type == .folder ? "folder.fill" : "doc.fill")
                        .foregroundStyle(DDTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(analysis.name)
                            .font(.dd(12, .medium))
                            .lineLimit(1)
                        Text(batchMetadata(analysis))
                            .font(.dd(11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.isSelected ? "Selected" : "Not selected"), \(analysis.name)")
        case .needsConnection:
            unavailableRow(item.link, icon: "lock.fill", message: tr("Sign in required", "ต้องลงชื่อเข้าใช้"))
        case .unavailable(let message):
            unavailableRow(item.link, icon: "exclamationmark.triangle.fill", message: message)
        }
    }

    private func unavailableRow(_ link: String, icon: String, message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(.orange)
            Text(message).font(.dd(11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 32)
        .help(link)
    }

    private func batchMetadata(_ analysis: DriveLinkAnalysis) -> String {
        var parts: [String] = []
        if let bytes = analysis.totalBytes { parts.append(Formatters.byteCount(bytes)) }
        if let count = analysis.fileCount { parts.append(tr("\(count) files", "\(count) ไฟล์")) }
        parts.append(analysis.isPublic ? tr("Public", "สาธารณะ") : tr("Private", "ส่วนตัว"))
        return parts.joined(separator: " · ")
    }
}

/// Shown when analysis succeeds: the item's details plus an explicit Download
/// confirm, so the destination can still be changed before anything is queued.
///
/// The destination row is repeated here rather than left to the paste box above.
/// Changing it was technically possible all along — the control sits above the
/// card — but on a video the card runs past 300pt, which puts a 10.5pt line of
/// text far enough from where the eye is that people reasonably conclude the
/// folder can't be changed at this point. It's shown where the decision is made.
struct AnalyzedPromptView: View {
    let analysis: DriveLinkAnalysis
    let destinationURL: URL?
    let preflight: DestinationPreflight
    let sourceLink: String
    let onChooseDestination: () -> Void
    let onSelectDestination: (URL) -> Void
    let onDownload: (_ asAudio: Bool, _ clipSection: String?, _ customName: String?) -> Void
    let onCancel: () -> Void

    /// The name to save under, editable before anything is queued. Seeded from
    /// the link's own name (without its extension — the extension is decided by
    /// what actually downloads, not by what is typed here).
    @State private var name = ""
    /// Whether the name was actually typed in. Not inferred by comparing the
    /// field to the analysis: a video card is rebuilt ~12s in with the title
    /// yt-dlp resolved, which can differ from the one oEmbed gave the field. The
    /// comparison then reads as "the user renamed it", and an untouched card
    /// would quietly pin the file to the older title.
    @State private var hasEditedName = false
    @State private var isEditingName = false
    @FocusState private var isNameFocused: Bool

    /// Video links can come down as the video itself or extracted MP3.
    @State private var asAudio = false
    /// Optional trim: only the "start–end" section is downloaded.
    @State private var trimEnabled = false
    @State private var trimStart = ""
    @State private var trimEnd = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if analysis.isVideo == true, let thumbnail = analysis.thumbnailURL, let url = URL(string: thumbnail) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
                // Taller than it was: this is the one picture on the screen the
                // user is deciding from, and at 110pt it read as a strip of
                // decoration beside the text rather than the thing being
                // confirmed. 150 still leaves the Download button on screen at
                // the 520pt cap, which a full-bleed poster would not.
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if let duration = analysis.durationSeconds {
                        Text(Self.timestamp(from: duration))
                            .font(.dd(11, .medium).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.65)))
                            .padding(6)
                    }
                }
                .accessibilityHidden(true)
            }

            HStack(spacing: 12) {
                Image(systemName: analysis.isVideo == true
                        ? "play.rectangle.fill"
                        : analysis.type == .folder ? "folder.fill" : "doc.fill")
                    .font(.dd(22))
                    .foregroundStyle(DDTheme.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    nameRow

                    HStack(spacing: 4) {
                        if let totalBytes = analysis.totalBytes {
                            Text(Formatters.byteCount(totalBytes))
                        }
                        if let fileCount = analysis.fileCount {
                            Text(tr("· \(fileCount) \(fileCount == 1 ? "file" : "files")", "· \(fileCount) ไฟล์"))
                        }
                        if let ownerName = analysis.ownerName {
                            Text(tr("· by \(ownerName)", "· โดย \(ownerName)"))
                        }
                    }
                    .font(.dd(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)
            }

            if analysis.isVideo == true {
                Picker(tr("Format", "รูปแบบ"), selection: $asAudio) {
                    Label(tr("Video", "วิดีโอ"), systemImage: "play.rectangle").tag(false)
                    Label("MP3", systemImage: "music.note").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Toggle(isOn: $trimEnabled.animation(.easeInOut(duration: 0.15))) {
                    Text(tr("Trim to a section", "ตัดเฉพาะช่วง"))
                        .font(.dd(11))
                }
                .toggleStyle(.checkbox)

                if trimEnabled {
                    HStack(spacing: 8) {
                        TextField("0:00", text: $trimStart)
                            .textFieldStyle(.roundedBorder)
                            .font(.dd(11).monospacedDigit())
                            .frame(width: 64)
                            .accessibilityLabel("Trim start time")

                        Text("–").foregroundStyle(.secondary)

                        TextField(analysis.durationSeconds.map(Self.timestamp(from:)) ?? "0:30", text: $trimEnd)
                            .textFieldStyle(.roundedBorder)
                            .font(.dd(11).monospacedDigit())
                            .frame(width: 64)
                            .accessibilityLabel("Trim end time")

                        Text(tr("min:sec", "นาที:วิ"))
                            .font(.dd(11))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)
                    }

                    if trimInvalid {
                        Text(tr("End must be after start (e.g. 0:10 – 1:30).", "เวลาจบต้องมากกว่าเวลาเริ่ม (เช่น 0:10 – 1:30)"))
                            .font(.dd(11))
                            .foregroundStyle(.orange)
                    }
                }
            }

            Divider()

            DestinationRow(
                destinationURL: destinationURL,
                isLocked: false,
                showsLabel: true,
                sourceLink: sourceLink,
                onChooseDestination: onChooseDestination,
                onSelectDestination: onSelectDestination
            )

            preflightView

            HStack(spacing: 10) {
                Button(tr("Cancel", "ยกเลิก"), role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)

                Button {
                    onDownload(asAudio, clipSection, customName)
                } label: {
                    Label(
                        asAudio ? tr("Add MP3 to queue", "เพิ่ม MP3 เข้าคิว") : tr("Add to queue", "เพิ่มเข้าคิว"),
                        systemImage: asAudio ? "music.note" : "plus.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimEnabled && trimInvalid || !preflight.canQueue)
                // Return confirms the card, carrying the format, trim and name
                // chosen on it. The paste box deliberately no longer answers
                // Return while this card is up: it can't see any of that.
                //
                // Except while the name is being typed, where Return means
                // "done with this field" — the field's own onSubmit and the
                // default button would otherwise both fire on one keypress and
                // the download would start before the folder could be checked.
                .keyboardShortcut(isEditingName ? nil : .defaultAction)
            }
        }
        .padding(16)
        .cardBackground()
        .transition(.opacity.combined(with: .move(edge: .top)))
        // The field follows the analysis until it is typed in, and stops the
        // moment it is: the background enrichment replaces `analysis` ~12s into
        // a video card, and re-seeding unconditionally there would wipe a name
        // already typed.
        .task(id: analysis.itemID) { seedNameIfUntouched() }
        .onChange(of: analysis.name) { _, _ in seedNameIfUntouched() }
    }

    private var preflightView: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: analysis.isPublic ? "eye" : "lock.fill")
                    .foregroundStyle(analysis.isPublic ? Color.secondary : Color.orange)
                Text(analysis.isPublic
                     ? tr("Public link", "ลิงก์สาธารณะ")
                     : tr("Private — uses your Google access", "ส่วนตัว — ใช้สิทธิ์ Google ของคุณ"))
            }

            HStack(spacing: 5) {
                Image(systemName: "internaldrive")
                Text(preflight.spaceDescription)
            }

            if preflight.hasNameCollision {
                Label(tr("A matching name exists — DropDrive will keep both files.", "พบชื่อซ้ำ — DropDrive จะเก็บทั้งสองไฟล์"), systemImage: "doc.on.doc")
                    .foregroundStyle(.orange)
            }
        }
        .font(.dd(11))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Name

    /// The name, as a label with a pencil until it's tapped, then a field. A
    /// permanently-drawn text box read as "type something here" on a card whose
    /// whole job is to confirm, and made the common case — download it under the
    /// name it already has — look like unfinished work.
    @ViewBuilder
    private var nameRow: some View {
        if isEditingName {
            HStack(spacing: 4) {
                // Typing goes through this setter; the seeding below writes
                // `name` directly and so can't mark the field as edited. An
                // .onChange here could not tell the two apart — it fires on the
                // next view update rather than inline, so a flag cleared right
                // after seeding is set back to true by the change that seeding
                // itself caused.
                TextField(seedName, text: Binding(
                    get: { name },
                    set: { typed in
                        name = typed
                        hasEditedName = true
                    }
                ))
                    .textFieldStyle(.plain)
                    .font(.dd(13, .medium))
                    .focused($isNameFocused)
                    .onSubmit { isEditingName = false }
                    .accessibilityLabel("File name")

                if !fileExtension.isEmpty {
                    Text(".\(fileExtension)")
                        .font(.dd(11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(DDTheme.rail)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(DDTheme.accent.opacity(0.5), lineWidth: 1)
                    }
            )
        } else {
            Button {
                isEditingName = true
                isNameFocused = true
            } label: {
                HStack(spacing: 5) {
                    Text(displayName)
                        .font(.dd(13, .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Image(systemName: "pencil")
                        .font(.dd(11))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tr("Rename before downloading", "เปลี่ยนชื่อก่อนดาวน์โหลด"))
            .accessibilityLabel("Rename \(displayName)")
        }
    }

    private func seedNameIfUntouched() {
        guard !hasEditedName else { return }
        name = seedName
    }

    /// Extension of the file as it exists on Drive. Folders have none, and a
    /// video's container isn't known until yt-dlp has picked a format.
    private var fileExtension: String {
        guard analysis.type != .folder, analysis.isVideo != true else { return "" }
        return (analysis.name as NSString).pathExtension
    }

    /// What the field starts with: the name minus the extension shown beside it.
    private var seedName: String {
        fileExtension.isEmpty ? analysis.name : (analysis.name as NSString).deletingPathExtension
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayName: String {
        guard hasEditedName, !trimmedName.isEmpty else { return analysis.name }
        return fileExtension.isEmpty ? trimmedName : "\(trimmedName).\(fileExtension)"
    }

    /// Nil when nothing was actually typed, so an untouched card queues exactly
    /// as it did before this field existed.
    private var customName: String? {
        guard hasEditedName, !trimmedName.isEmpty, trimmedName != seedName else { return nil }
        return trimmedName
    }

    // MARK: - Trim parsing

    /// "start-end" in whole seconds for yt-dlp's --download-sections, or nil
    /// when trimming is off / fields are empty.
    private var clipSection: String? {
        guard trimEnabled else { return nil }
        // A malformed (non-empty) start used to fall back to 0 silently, so a typo
        // trimmed from the beginning of the video instead of being rejected.
        guard trimStart.isEmpty || Self.seconds(from: trimStart) != nil else { return nil }
        let start = Self.seconds(from: trimStart) ?? 0
        guard let end = Self.seconds(from: trimEnd), end > start else { return nil }
        return "\(Int(start))-\(Int(end))"
    }

    private var trimInvalid: Bool {
        guard trimEnabled else { return false }
        // A non-empty, unparsable start is a real wrong input, same as the end field.
        if !trimStart.isEmpty, Self.seconds(from: trimStart) == nil { return true }
        // Empty end = nothing to cut yet; only flag a real, wrong input.
        guard Self.seconds(from: trimEnd) != nil || !trimEnd.isEmpty else { return false }
        return clipSection == nil
    }

    /// Accepts "90", "1:30", or "1:02:30".
    private static func seconds(from text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var total: Double = 0
        for part in parts {
            guard let value = Double(part), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }

    private static func timestamp(from seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Shown when a pasted link matches an item that already completed this session,
/// asking whether to queue a fresh copy of it.
struct DuplicateCompletedPromptView: View {
    let analysis: DriveLinkAnalysis
    let onDownloadAgain: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: analysis.type == .folder ? "folder.fill" : "doc.fill")
                    .font(.dd(22))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(analysis.name)
                        .font(.dd(13, .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(tr("You've already downloaded this", "เคยดาวน์โหลดรายการนี้แล้ว"))
                        .font(.dd(11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 16) {
                    if let totalBytes = analysis.totalBytes {
                        detail(Formatters.byteCount(totalBytes), icon: "internaldrive")
                    } else {
                        detail(tr("Size unknown", "ไม่ทราบขนาด"), icon: "internaldrive")
                    }

                    if let fileCount = analysis.fileCount {
                        detail(tr("\(fileCount) \(fileCount == 1 ? "file" : "files")", "\(fileCount) ไฟล์"), icon: "doc.on.doc")
                    }
                }

                if let ownerName = analysis.ownerName {
                    detail(tr("Owned by \(ownerName)", "เจ้าของ: \(ownerName)"), icon: "person.crop.circle")
                }
            }
            .font(.dd(11))
            .foregroundStyle(.secondary)

            Text(tr("Download again?", "ดาวน์โหลดอีกครั้ง?"))
                .font(.dd(13, .medium))

            HStack(spacing: 10) {
                Button(tr("Cancel", "ยกเลิก"), role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)

                Button(action: onDownloadAgain) {
                    Label(tr("Download Again", "ดาวน์โหลดอีกครั้ง"), systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .cardBackground()
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func detail(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
    }
}

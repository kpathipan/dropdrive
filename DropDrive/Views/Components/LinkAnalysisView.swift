import SwiftUI

struct LinkAnalyzingView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text(tr("Analyzing link…", "กำลังวิเคราะห์ลิงก์…"))
                .font(.dd(12.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground()
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
}

struct LinkInvalidView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(tr("That doesn't look like a Google Drive link.", "ลิงก์นี้ดูไม่ใช่ลิงก์ Google Drive"))
                .font(.dd(12.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
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
                .font(.dd(12.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(isSigningIn ? tr("Connecting…", "กำลังเชื่อมต่อ…") : tr("Connect", "เชื่อมต่อ"), action: onConnect)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSigningIn)
                .accessibilityLabel("Connect Google Drive")
        }
        .padding(14)
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
                .font(.dd(12.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
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
                .font(.dd(12.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(tr("Retry", "ลองใหม่"), action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(14)
        .cardBackground()
        .transition(.opacity)
    }
}

/// Shown when analysis succeeds: the item's details plus an explicit Download
/// confirm, so the destination can still be changed before anything is queued.
struct AnalyzedPromptView: View {
    let analysis: DriveLinkAnalysis
    let onDownload: (_ asAudio: Bool) -> Void
    let onCancel: () -> Void

    /// Video links can come down as the video itself or extracted MP3.
    @State private var asAudio = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: analysis.isVideo == true
                        ? "play.rectangle.fill"
                        : analysis.type == .folder ? "folder.fill" : "doc.fill")
                    .font(.dd(22))
                    .foregroundStyle(DDTheme.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(analysis.name)
                        .font(.dd(13, .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

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
                    .font(.dd(11))
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
            }

            HStack(spacing: 10) {
                Button(tr("Cancel", "ยกเลิก"), role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)

                Button {
                    onDownload(asAudio)
                } label: {
                    Label(
                        asAudio ? tr("Download MP3", "ดาวน์โหลด MP3") : tr("Download", "ดาวน์โหลด"),
                        systemImage: asAudio ? "music.note" : "arrow.down.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .cardBackground()
        .transition(.opacity.combined(with: .move(edge: .top)))
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
                .font(.dd(12.5, .medium))

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

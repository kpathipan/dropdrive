import SwiftUI

/// The update offer, on the main screen rather than buried in Preferences.
///
/// The notification's "Update now" button installs directly, but someone who
/// misses the notification and simply opens the app had no way to find out an
/// update existed without going to Preferences → About. This puts it where they
/// already are, and disappears entirely when there's nothing to offer.
struct UpdateBanner: View {
    @State private var updates = UpdateService.shared
    @State private var showingNotes = false

    var body: some View {
        switch updates.state {
        case .available(let release):
            card {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.dd(17))
                            .foregroundStyle(DDTheme.accent)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(tr("Version \(release.version) is available", "มีเวอร์ชัน \(release.version)"))
                                .font(.dd(13, .medium))
                            Text(Formatters.byteCount(release.sizeBytes))
                                .font(.dd(11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Button(tr("Update", "อัปเดต")) { updates.installUpdate() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }

                    ReleaseNotesDisclosure(notes: release.fullNotes, isExpanded: $showingNotes)
                }
            }

        case .downloading(let progress):
            card {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("Downloading the update…", "กำลังดาวน์โหลดอัปเดต…"))
                        .font(.dd(11))
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                    UpdateProgressDetail(progress: progress)
                }
            }

        case .installing:
            card {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(tr("Installing — DropDrive will reopen…", "กำลังติดตั้ง — แอพจะเปิดใหม่เอง…"))
                        .font(.dd(11))
                        .foregroundStyle(.secondary)
                }
            }

        case .failed(let message):
            // Only surfaced here once an update was actually on offer; a failed
            // background check shouldn't put an error on the main screen.
            if updates.hasOfferedUpdate {
                card {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.dd(13))
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.dd(11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 4)

                        // Most of these failures are things the user can fix and
                        // retry — a running download, a dropped connection — so
                        // the offer has to be reachable again.
                        Button(tr("Try again", "ลองใหม่")) { updates.retryOffer() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }

        case .idle, .checking, .upToDate:
            EmptyView()
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// "What's new", collapsed by default. The notes come from the release's
/// CHANGELOG section and can run long, so the expanded form scrolls inside a
/// fixed height rather than growing the popover past its limit.
struct ReleaseNotesDisclosure: View {
    let notes: String
    @Binding var isExpanded: Bool

    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.right")
                            .font(.dd(11, .semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text(tr("What's new", "มีอะไรใหม่"))
                            .font(.dd(11))
                    }
                    .foregroundStyle(DDTheme.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Show what's new in this update", "ดูรายละเอียดอัปเดตนี้"))

                if isExpanded {
                    ScrollView {
                        Text(notes)
                            .font(.dd(11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 150)
                }
            }
        }
    }
}

/// The line under the update's progress bar: how much has arrived, how fast, and
/// how long is left. Shared by the banner and Preferences so the update reads
/// the same way in both, and the same way a file download does.
///
/// The percentage on its own was not enough. 68 MB over a slow connection can
/// hold the same number for minutes, and with nothing else on screen there is no
/// way to tell a slow update from a stalled one — which is exactly the wrong
/// thing to leave ambiguous about a process that replaces the app.
struct UpdateProgressDetail: View {
    let progress: UpdateService.Progress

    var body: some View {
        HStack(spacing: 4) {
            Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()

            if progress.totalBytes > 0 {
                Text("· \(Formatters.byteCount(progress.bytesWritten)) / \(Formatters.byteCount(progress.totalBytes))")
            }

            if progress.bytesPerSecond > 0 {
                Text("· \(Formatters.transferSpeed(progress.bytesPerSecond))")
            }

            if let etaSeconds = progress.etaSeconds, let remaining = Formatters.remainingTime(etaSeconds) {
                Text("· \(remaining)")
            }
        }
        .font(.dd(11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

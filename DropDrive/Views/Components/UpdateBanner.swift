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
                                .font(.dd(12, .medium))
                            Text(Formatters.byteCount(release.sizeBytes))
                                .font(.dd(10.5))
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

        case .downloading(let fraction):
            card {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("Downloading the update…", "กำลังดาวน์โหลดอัปเดต…"))
                        .font(.dd(11.5))
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.dd(10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

        case .installing:
            card {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(tr("Installing — DropDrive will reopen…", "กำลังติดตั้ง — แอพจะเปิดใหม่เอง…"))
                        .font(.dd(11.5))
                        .foregroundStyle(.secondary)
                }
            }

        case .failed(let message):
            // Only surfaced here once an update was actually on offer; a failed
            // background check shouldn't put an error on the main screen.
            if updates.hasOfferedUpdate {
                card {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.dd(12))
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.dd(10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
                            .font(.dd(9, .semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text(tr("What's new", "มีอะไรใหม่"))
                            .font(.dd(10.5))
                    }
                    .foregroundStyle(DDTheme.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Show what's new in this update", "ดูรายละเอียดอัปเดตนี้"))

                if isExpanded {
                    ScrollView {
                        Text(notes)
                            .font(.dd(10.5))
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

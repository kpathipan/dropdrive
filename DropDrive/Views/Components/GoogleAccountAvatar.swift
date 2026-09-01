import SwiftUI

/// One reusable Google identity mark for the header, account hub, and Drive
/// review card. A photo remains the primary representation; initials and the
/// person symbol are resilient fallbacks rather than a separate visual system.
struct GoogleAccountAvatar: View {
    let account: GoogleAccount?
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let account {
                AsyncImage(url: account.profileImageURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        initialCircle(String(account.name.prefix(1)).uppercased())
                    }
                }
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: size * 0.78))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(DDTheme.border, lineWidth: 0.5) }
        .accessibilityHidden(true)
    }

    private func initialCircle(_ text: String) -> some View {
        Circle()
            .fill(DDTheme.accent)
            .overlay {
                Text(text.isEmpty ? "G" : text)
                    .font(.dd(max(9, size * 0.46), .semibold))
                    .foregroundStyle(.white)
            }
    }
}

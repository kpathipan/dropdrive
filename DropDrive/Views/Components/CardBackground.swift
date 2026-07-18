import SwiftUI

/// The popover's palette: white cards on a cool light-gray canvas, or their
/// warm-dark counterparts, with one blue accent. Every color reads
/// `AppTheme.shared.isDark` through Observation, so a theme change (in
/// Preferences or, in system mode, macOS itself) re-renders everything live.
/// MenuBarView pins the matching `.colorScheme` so `.primary`/`.secondary`
/// text follows along.
enum DDTheme {
    private static var dark: Bool { AppTheme.shared.isDark }

    static var canvas: Color {
        dark ? Color(red: 0.086, green: 0.094, blue: 0.114)            // #16181D
             : Color(red: 0.965, green: 0.973, blue: 0.984)            // #F6F8FB
    }

    static var rail: Color {
        dark ? Color(red: 0.106, green: 0.118, blue: 0.141)            // #1B1E24
             : Color(red: 0.929, green: 0.941, blue: 0.961)            // #EDF0F5
    }

    static var card: Color {
        dark ? Color(red: 0.137, green: 0.149, blue: 0.176)            // #23262D
             : .white
    }

    static var border: Color {
        dark ? Color(red: 0.220, green: 0.235, blue: 0.267)            // #383C44
             : Color(red: 0.835, green: 0.855, blue: 0.890)            // #D5DAE3
    }

    /// Brighter in dark mode — #2563EB reads muddy on near-black.
    static var accent: Color {
        dark ? Color(red: 0.298, green: 0.525, blue: 1.0)              // #4C86FF
             : Color(red: 0.145, green: 0.388, blue: 0.922)            // #2563EB
    }

    static var accentSoft: Color {
        dark ? Color(red: 0.298, green: 0.525, blue: 1.0).opacity(0.16)
             : Color(red: 0.918, green: 0.941, blue: 0.996)            // #EAF0FE
    }
}

extension Font {
    /// App-wide typeface: Sukhumvit Set, the loopless Thai family bundled with
    /// macOS (its Latin glyphs read cleanly too). Sizes are passed at the old
    /// system-font values and rendered one point smaller across the board.
    static func dd(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        if weight == .bold || weight == .heavy || weight == .black {
            name = "SukhumvitSet-Bold"
        } else if weight == .semibold {
            name = "SukhumvitSet-SemiBold"
        } else if weight == .medium {
            name = "SukhumvitSet-Medium"
        } else if weight == .light || weight == .thin || weight == .ultraLight {
            name = "SukhumvitSet-Light"
        } else {
            name = "SukhumvitSet-Text"
        }
        return .custom(name, size: size - 1)
    }
}

struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background(DDTheme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DDTheme.border, lineWidth: 0.5)
            }
    }
}

struct InputFieldBackground: ViewModifier {
    var cornerRadius: CGFloat = 9

    func body(content: Content) -> some View {
        content
            .background(DDTheme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DDTheme.border, lineWidth: 0.5)
            }
    }
}

extension View {
    func cardBackground(cornerRadius: CGFloat = 10) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }

    func inputFieldBackground(cornerRadius: CGFloat = 9) -> some View {
        modifier(InputFieldBackground(cornerRadius: cornerRadius))
    }
}

import SwiftUI

/// The popover's palette: white cards on a neutral grey canvas, or their dark
/// counterparts, with one blue accent.
///
/// The greys are deliberately neutral rather than blue-cast. They used to carry
/// a blue tint of their own, which put the whole window a half-step toward the
/// accent — so the accent stopped reading as a colour and started reading as a
/// tint over everything. One saturated colour only looks chosen when what
/// surrounds it is not competing with it. Every color reads
/// `AppTheme.shared.isDark` through Observation, so a theme change (in
/// Preferences or, in system mode, macOS itself) re-renders everything live.
/// MenuBarView pins the matching `.colorScheme` so `.primary`/`.secondary`
/// text follows along.
enum DDTheme {
    private static var dark: Bool { AppTheme.shared.isDark }

    static var canvas: Color {
        dark ? Color(red: 0.106, green: 0.106, blue: 0.114)            // #1B1B1D
             : Color(red: 0.961, green: 0.961, blue: 0.969)            // #F5F5F7
    }


    static var rail: Color {
        dark ? Color(red: 0.125, green: 0.125, blue: 0.133)            // #202022
             : Color(red: 0.929, green: 0.929, blue: 0.937)            // #EDEDEF
    }

    static var card: Color {
        dark ? Color(red: 0.149, green: 0.149, blue: 0.157)            // #262628
             : .white
    }

    static var border: Color {
        dark ? Color(red: 0.227, green: 0.227, blue: 0.239)            // #3A3A3D
             : Color(red: 0.890, green: 0.890, blue: 0.902)            // #E3E3E6
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

    static var success: Color { dark ? Color(red: 0.35, green: 0.82, blue: 0.56) : Color(red: 0.10, green: 0.58, blue: 0.30) }
    static var warning: Color { dark ? Color(red: 1.0, green: 0.68, blue: 0.25) : Color(red: 0.84, green: 0.43, blue: 0.05) }
}

/// One spacing/radius scale for the compact popover and the larger settings
/// window. Keeping these here stops each new card from inventing a subtly
/// different inset or corner radius.
enum DDMetrics {
    static let compact: CGFloat = 6
    static let controlGap: CGFloat = 8
    static let standard: CGFloat = 12
    static let section: CGFloat = 16
    static let contentInset: CGFloat = 16
    static let controlHeight: CGFloat = 38
    static let inputRadius: CGFloat = 11
    static let cardRadius: CGFloat = 14
}

extension Font {
    /// Use the system text face rather than a custom family. macOS supplies SF
    /// Pro for Latin and its own matching Thai fallback, which preserves the
    /// platform's Dynamic Type metrics and makes mixed Thai/English content read
    /// like part of the OS instead of a separately styled panel.
    static func dd(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = DDMetrics.cardRadius

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
    var cornerRadius: CGFloat = DDMetrics.inputRadius

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
    func cardBackground(cornerRadius: CGFloat = DDMetrics.cardRadius) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }

    func inputFieldBackground(cornerRadius: CGFloat = DDMetrics.inputRadius) -> some View {
        modifier(InputFieldBackground(cornerRadius: cornerRadius))
    }
}

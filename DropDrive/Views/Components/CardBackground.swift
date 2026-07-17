import SwiftUI

/// The fixed light palette the popover uses in every system appearance —
/// the design is white cards on a cool light-gray canvas with one blue accent,
/// and it doesn't invert. MenuBarView pins `.colorScheme(.light)` to match.
enum DDTheme {
    static let canvas = Color(red: 0.965, green: 0.973, blue: 0.984)   // #F6F8FB
    static let rail = Color(red: 0.929, green: 0.941, blue: 0.961)     // #EDF0F5
    static let card = Color.white
    static let border = Color(red: 0.835, green: 0.855, blue: 0.890)   // #D5DAE3
    static let accent = Color(red: 0.145, green: 0.388, blue: 0.922)   // #2563EB
    static let accentSoft = Color(red: 0.918, green: 0.941, blue: 0.996) // #EAF0FE
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

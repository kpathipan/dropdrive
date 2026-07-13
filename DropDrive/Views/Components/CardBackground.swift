import SwiftUI

struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 12

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 3)
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }
}

struct InputFieldBackground: ViewModifier {
    var cornerRadius: CGFloat = 9

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(fillColor, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
    }

    private var fillColor: Color {
        colorScheme == .dark ? .black.opacity(0.18) : .black.opacity(0.045)
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.06) : .black.opacity(0.08)
    }
}

extension View {
    func cardBackground(cornerRadius: CGFloat = 12) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }

    func inputFieldBackground(cornerRadius: CGFloat = 9) -> some View {
        modifier(InputFieldBackground(cornerRadius: cornerRadius))
    }
}

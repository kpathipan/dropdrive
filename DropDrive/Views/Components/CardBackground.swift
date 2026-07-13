import SwiftUI

struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 3)
    }
}

struct InputFieldBackground: ViewModifier {
    var cornerRadius: CGFloat = 9

    func body(content: Content) -> some View {
        content
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            }
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

import SwiftUI

enum KXCardStyle {
    /// White card with soft shadow.
    case raised
    /// Pale teal tinted panel (used to group content inside screens).
    case tinted
    /// Orange-tinted highlight (live cues, alerts).
    case accent
}

struct KXCardModifier: ViewModifier {
    var style: KXCardStyle
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
            .shadow(color: style == .raised ? KXShadow.color : .clear, radius: KXShadow.radius, y: KXShadow.y)
    }

    private var background: Color {
        switch style {
        case .raised: return KXColor.surface
        case .tinted: return KXColor.surfaceTint
        case .accent: return KXColor.accentSoft
        }
    }
}

extension View {
    func kxCard(_ style: KXCardStyle = .raised, padding: CGFloat = KXSpacing.lg) -> some View {
        modifier(KXCardModifier(style: style, padding: padding))
    }
}

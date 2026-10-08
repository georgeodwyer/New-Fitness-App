import SwiftUI

/// Pill buttons matching the design's Primary / Secondary / Inverted / Outlined set.
struct KXButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary, inverted, outlined }

    var variant: Variant = .primary
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(KXFont.bodyEmphasis)
            .foregroundStyle(foreground)
            .padding(.horizontal, KXSpacing.xl)
            .padding(.vertical, KXSpacing.md)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
            .background(background, in: Capsule())
            .overlay {
                if variant == .outlined {
                    Capsule().strokeBorder(KXColor.border, lineWidth: 1.5)
                }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch variant {
        case .primary: return KXColor.onAccent
        case .secondary: return KXColor.accent
        case .inverted: return KXColor.onInverted
        case .outlined: return KXColor.ink
        }
    }

    private var background: Color {
        switch variant {
        case .primary: return KXColor.accent
        case .secondary: return KXColor.accentSoft
        case .inverted: return KXColor.inverted
        case .outlined: return .clear
        }
    }
}

extension ButtonStyle where Self == KXButtonStyle {
    static var kxPrimary: KXButtonStyle { KXButtonStyle(variant: .primary) }
    static var kxSecondary: KXButtonStyle { KXButtonStyle(variant: .secondary) }
    static var kxInverted: KXButtonStyle { KXButtonStyle(variant: .inverted) }
    static var kxOutlined: KXButtonStyle { KXButtonStyle(variant: .outlined) }
    static func kx(_ variant: KXButtonStyle.Variant, fullWidth: Bool = false) -> KXButtonStyle {
        KXButtonStyle(variant: variant, fullWidth: fullWidth)
    }
}

/// Round icon button (bell, play, +/-).
struct KXIconButton: View {
    enum Variant { case accent, neutral, tinted }

    let systemImage: String
    let accessibilityLabel: String
    var variant: Variant = .neutral
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(background, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var foreground: Color {
        switch variant {
        case .accent: return KXColor.onAccent
        case .neutral: return KXColor.ink
        case .tinted: return KXColor.accent
        }
    }

    private var background: Color {
        switch variant {
        case .accent: return KXColor.accent
        case .neutral: return KXColor.surface
        case .tinted: return KXColor.accentSoft
        }
    }
}

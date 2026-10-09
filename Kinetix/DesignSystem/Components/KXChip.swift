import SwiftUI

/// Small pill label or selectable chip ("Popular", "Adaptive Split", day pickers).
struct KXChip: View {
    enum Variant { case primary, secondary, inverted, outlined, success, warning, danger }

    let text: String
    var systemImage: String?
    var variant: Variant = .secondary

    var body: some View {
        HStack(spacing: KXSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(KXFont.captionEmphasis)
        .foregroundStyle(foreground)
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, KXSpacing.xs + 2)
        .background(background, in: Capsule())
        .overlay {
            if variant == .outlined {
                Capsule().strokeBorder(KXColor.border, lineWidth: 1)
            }
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary: return KXColor.onAccent
        case .secondary: return KXColor.accent
        case .inverted: return KXColor.onInverted
        case .outlined: return KXColor.inkSecondary
        // Status chips keep ink text; the tinted background and icon carry the status.
        case .success, .warning, .danger: return KXColor.ink
        }
    }

    private var background: Color {
        switch variant {
        case .primary: return KXColor.accent
        case .secondary: return KXColor.accentSoft
        case .inverted: return KXColor.inverted
        case .outlined: return .clear
        case .success: return KXColor.success.opacity(0.16)
        case .warning: return KXColor.warning.opacity(0.22)
        case .danger: return KXColor.danger.opacity(0.16)
        }
    }
}

/// Selectable chip used for multiple-choice answers (e.g. training days).
struct KXSelectableChip: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(KXFont.captionEmphasis)
                .foregroundStyle(isSelected ? KXColor.onAccent : KXColor.ink)
                .padding(.horizontal, KXSpacing.md)
                .padding(.vertical, KXSpacing.sm)
                .frame(minWidth: 44, minHeight: 36)
                .background(isSelected ? KXColor.accent : KXColor.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(isSelected ? .clear : KXColor.border, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

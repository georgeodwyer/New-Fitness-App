import SwiftUI

/// Screen header from the designs: logo + "KINETIX" overline, screen title,
/// notification bell and avatar.
struct KXScreenHeader: View {
    let title: String
    var onNotifications: (() -> Void)?

    var body: some View {
        HStack(spacing: KXSpacing.md) {
            KXLogo(size: 32)
            VStack(alignment: .leading, spacing: 0) {
                KXOverline("Kinetix")
                Text(title)
                    .font(KXFont.title)
                    .foregroundStyle(KXColor.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            if let onNotifications {
                KXIconButton(systemImage: "bell", accessibilityLabel: "Notifications", size: 36, action: onNotifications)
            }
        }
    }
}

/// Placeholder brand mark: a dark disc with an orange "K" stroke.
struct KXLogo: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(KXColor.inverted)
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(KXColor.accent)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

import SwiftUI

/// Large selectable answer card used in onboarding ("Hybrid Athlete", "Full gym").
struct KXOptionCard: View {
    let title: String
    var detail: String?
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: KXSpacing.md) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(isSelected ? KXColor.onAccent : KXColor.inkSecondary)
                        .frame(width: 44, height: 44)
                        .background(isSelected ? KXColor.accent : KXColor.surfaceTint, in: Circle())
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    Text(title)
                        .font(KXFont.headline)
                        .foregroundStyle(KXColor.ink)
                    if let detail {
                        Text(detail)
                            .font(KXFont.caption)
                            .foregroundStyle(KXColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: KXSpacing.sm)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? KXColor.accent : KXColor.border)
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .kxCard(isSelected ? .accent : .raised)
            .overlay {
                RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                    .strokeBorder(isSelected ? KXColor.accent : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

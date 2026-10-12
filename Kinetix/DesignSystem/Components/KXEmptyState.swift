import SwiftUI

/// A friendly placeholder for a section with nothing in it yet.
struct KXEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.md) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(KXColor.accent)
                .frame(width: 40, height: 40)
                .background(KXColor.accentSoft, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Text(message).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

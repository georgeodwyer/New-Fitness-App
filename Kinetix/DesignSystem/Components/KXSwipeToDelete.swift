import SwiftUI

/// Swipe a card left to reveal a red Delete button behind it; tap Delete to remove it.
/// Tapping the card or swiping back closes it. Only mostly-sideways drags count, so the page
/// still scrolls normally.
struct KXSwipeToDelete<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat = 0
    @State private var isSwiping = false

    private let buttonWidth: CGFloat = 88

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                Button(role: .destructive) {
                    withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
                    onDelete()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                        Text("Delete").font(KXFont.captionEmphasis)
                    }
                    .foregroundStyle(.white)
                    .frame(width: buttonWidth)
                    .frame(maxHeight: .infinity)
                    .background(KXColor.danger, in: RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
            content()
                .offset(x: offset)
                .overlay {
                    // While open, a tap on the card closes it instead of opening it.
                    if offset < 0 && !isSwiping {
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { offset = 0 } }
                            .offset(x: offset)
                    }
                }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                    guard isSwiping || horizontal else { return }
                    if !isSwiping { isSwiping = true; startOffset = offset }
                    offset = min(0, max(startOffset + value.translation.width, -buttonWidth - 30))
                }
                .onEnded { _ in
                    guard isSwiping else { return }
                    isSwiping = false
                    withAnimation(.easeOut(duration: 0.2)) {
                        offset = offset < -buttonWidth / 2 ? -(buttonWidth + KXSpacing.sm) : 0
                    }
                }
        )
        .accessibilityAction(named: "Delete", onDelete)
    }
}

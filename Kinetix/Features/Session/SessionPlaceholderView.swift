import SwiftUI

/// Full-screen trainer container. Strength (Milestone 3) and running
/// (Milestone 4) trainers replace this.
struct SessionPlaceholderView: View {
    let session: ActiveSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: KXSpacing.xl) {
            HStack {
                Spacer()
                KXIconButton(systemImage: "xmark", accessibilityLabel: "Close", action: { dismiss() })
            }
            Spacer()
            Image(systemName: session.kind.symbolName)
                .font(.system(size: 56))
                .foregroundStyle(KXColor.accent)
                .accessibilityHidden(true)
            Text(session.title)
                .font(KXFont.title)
                .foregroundStyle(KXColor.ink)
            Text("The live trainer for this session is coming in a later milestone.")
                .font(KXFont.callout)
                .foregroundStyle(KXColor.inkSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Close") { dismiss() }
                .buttonStyle(.kx(.inverted, fullWidth: true))
        }
        .padding(KXSpacing.screenMargin)
        .background(KXColor.background.ignoresSafeArea())
    }
}

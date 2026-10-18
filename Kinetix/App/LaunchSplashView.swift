import SwiftUI

/// Shown briefly when the app starts: the Kinetix mark springs in, then the wordmark fades
/// up. With Reduce Motion on, it simply fades.
struct LaunchSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var markScale: CGFloat = 0.6
    @State private var markOpacity: Double = 0
    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkOffset: CGFloat = 8
    @State private var pulse = false

    var body: some View {
        ZStack {
            KXColor.background.ignoresSafeArea()
            VStack(spacing: KXSpacing.lg) {
                KXLogo(size: 104)
                    .scaleEffect(markScale * (pulse ? 1.03 : 1))
                    .opacity(markOpacity)
                KXWordmark(height: 28)
                    .opacity(wordmarkOpacity)
                    .offset(y: wordmarkOffset)
                Text("Run. Lift. Balanced.")
                    .font(KXFont.callout)
                    .foregroundStyle(KXColor.inkSecondary)
                    .opacity(wordmarkOpacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kinetix")
        .onAppear(perform: animate)
    }

    private func animate() {
        guard !reduceMotion else {
            markScale = 1; wordmarkOffset = 0
            withAnimation(.easeOut(duration: 0.3)) { markOpacity = 1; wordmarkOpacity = 1 }
            return
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
            markScale = 1
            markOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
            wordmarkOpacity = 1
            wordmarkOffset = 0
        }
        withAnimation(.easeInOut(duration: 0.6).delay(0.7).repeatForever(autoreverses: true)) { pulse = true }
    }
}

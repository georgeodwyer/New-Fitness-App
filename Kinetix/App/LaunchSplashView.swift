import SwiftUI

/// Shown briefly when the app starts: the Kinetix mark draws its ring, the bolt pops in and
/// the wordmark fades up. With Reduce Motion on, it simply fades.
struct LaunchSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringProgress: CGFloat = 0
    @State private var boltScale: CGFloat = 0.4
    @State private var boltOpacity: Double = 0
    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkOffset: CGFloat = 8
    @State private var pulse = false

    var body: some View {
        ZStack {
            KXColor.background.ignoresSafeArea()
            VStack(spacing: KXSpacing.lg) {
                ZStack {
                    Circle()
                        .fill(KXColor.inverted)
                        .frame(width: 96, height: 96)
                        .scaleEffect(pulse ? 1.04 : 1)
                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(KXColor.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 112, height: 112)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(KXColor.accent)
                        .scaleEffect(boltScale)
                        .opacity(boltOpacity)
                }
                Text("KINETIX")
                    .font(.system(.title2, design: .default, weight: .heavy))
                    .tracking(6)
                    .foregroundStyle(KXColor.ink)
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
            ringProgress = 1; boltScale = 1; boltOpacity = 1; wordmarkOffset = 0
            withAnimation(.easeOut(duration: 0.3)) { wordmarkOpacity = 1 }
            return
        }
        withAnimation(.easeInOut(duration: 0.7)) { ringProgress = 1 }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.25)) {
            boltScale = 1
            boltOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.45)) {
            wordmarkOpacity = 1
            wordmarkOffset = 0
        }
        withAnimation(.easeInOut(duration: 0.6).delay(0.7).repeatForever(autoreverses: true)) { pulse = true }
    }
}

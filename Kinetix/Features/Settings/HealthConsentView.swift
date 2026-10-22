import SwiftUI

/// Explicit consent to use health data (UK GDPR special category data), asked once before
/// Apple Health is connected, separate from the terms. Withdrawn by stopping Apple Health.
enum HealthDataConsent {
    private static let agreedKey = "consent.healthData.agreedAt"
    private static let versionKey = "consent.healthData.version"
    /// Bump when what's read or why changes, to ask again.
    static let currentVersion = 1

    static var hasAgreed: Bool {
        UserDefaults.standard.object(forKey: agreedKey) != nil
            && UserDefaults.standard.integer(forKey: versionKey) >= currentVersion
    }

    static var agreedAt: Date? { UserDefaults.standard.object(forKey: agreedKey) as? Date }

    static func agree(now: Date = .now) {
        UserDefaults.standard.set(now, forKey: agreedKey)
        UserDefaults.standard.set(currentVersion, forKey: versionKey)
    }

    static func withdraw() {
        UserDefaults.standard.removeObject(forKey: agreedKey)
        UserDefaults.standard.removeObject(forKey: versionKey)
    }
}

/// "Use your health data?": what Kinetix reads, why, where it stays, and how to stop.
struct HealthConsentView: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(KXColor.accent)
                        .accessibilityHidden(true)
                    Text("Use your health data?")
                        .font(KXFont.title).foregroundStyle(KXColor.ink)
                    Text("Health data needs your clear permission. Here's exactly what Kinetix does with it.")
                        .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    point("eye", "What it reads",
                          "Heart rate, resting heart rate, HRV, sleep, steps, active energy, VO\u{2082} max, breathing rate and workouts from other apps. Apple then lets you choose which of these to share.")
                    point("figure.run", "Why",
                          "To work out your recovery and exertion, show your body trends, show heart rate during runs and adjust your plan when you need it.")
                    point("iphone", "Where it stays",
                          "Readings are read fresh from Apple Health on this iPhone and aren't stored by Kinetix or sent to our servers. Heart rate recorded during a Kinetix run is kept with that run.")
                    point("hand.raised", "Your choice",
                          "Kinetix works without it. You can stop any time in Settings \u{2192} Integrations \u{2192} Apple Health, or in the Health app.")
                    Text("This is training guidance, not medical advice.")
                        .font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                }
                .padding(KXSpacing.screenMargin)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: KXSpacing.sm) {
                    Button("I agree, connect Apple Health") {
                        HealthDataConsent.agree()
                        onAgree()
                    }
                    .buttonStyle(.kx(.primary, fullWidth: true))
                    .accessibilityIdentifier("consent.health.agree")
                    Button("Not now", action: onDecline)
                        .buttonStyle(.kx(.outlined, fullWidth: true))
                }
                .padding(KXSpacing.screenMargin)
                .background(KXColor.background)
            }
            .background(KXColor.background.ignoresSafeArea())
        }
        .tint(KXColor.accent)
    }

    private func point(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: KXSpacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(KXColor.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Text(text).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

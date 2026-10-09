import SwiftUI

/// Health & safety information (also needed for App Store review of fitness apps).
struct HealthDisclaimerView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                KXAccentHeadline(plain: "Train", accented: "safely")
                item("stethoscope", "Not medical advice",
                     "Kinetix gives general training guidance. It isn't a medical device and doesn't diagnose, treat or prevent any condition.")
                item("heart.text.square", "Check with a professional",
                     "Talk to a doctor before starting a new exercise programme, especially if you're new to exercise, pregnant, have a medical condition or injury, or take medication.")
                item("exclamationmark.triangle", "Stop if something feels wrong",
                     "Stop exercising and get medical help if you feel chest pain, faintness, severe breathlessness, dizziness or unusual pain.")
                item("figure.run", "Run aware",
                     "Keep your music low enough to hear traffic and people around you. Audio cues are designed to be brief, but your surroundings come first.")
                item("chart.line.uptrend.xyaxis", "Load figures are estimates",
                     "Training load, pace zones, race predictions and readiness are estimates based on what you log. Listen to your body over the numbers.")
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle("Health & safety")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func item(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: KXSpacing.md) {
            Image(systemName: symbol).font(.title3).foregroundStyle(KXColor.accent).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Text(title).font(KXFont.headline).foregroundStyle(KXColor.ink)
                Text(text).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .kxCard()
        .accessibilityElement(children: .combine)
    }
}

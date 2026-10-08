import SwiftUI
import SwiftData

/// First screen of onboarding. The full question flow arrives in Milestone 2;
/// for now this offers a sample profile so the rest of the app can be explored.
struct OnboardingWelcomeView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                KXStepProgress(step: 1, total: 4)
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    KXAccentHeadline(plain: "Calibrate your", accented: "Hybrid Engine")
                    Text("Running and strength, programmed together so one never undermines the other.")
                        .font(KXFont.body)
                        .foregroundStyle(KXColor.inkSecondary)
                }
                HStack {
                    KXOverline("Primary athletic focus")
                    Spacer()
                    KXChip(text: "Adaptive split", systemImage: "bolt.fill", variant: .secondary)
                }
                VStack(spacing: KXSpacing.md) {
                    focusCard(title: "Hybrid Athlete", detail: "Equal split: run engine alongside compound strength.", symbol: "figure.run.circle", selected: true)
                    focusCard(title: "Run Performance", detail: "5K to marathon goals with joint-resilient lifting.", symbol: "stopwatch", selected: false)
                    focusCard(title: "Max Strength & Power", detail: "Barbell progression backed by easy aerobic running.", symbol: "dumbbell", selected: false)
                }
                Text("The full onboarding questions arrive in the next milestone.")
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkTertiary)
                Button("Explore with a sample profile") {
                    SampleData.seed(into: context)
                }
                .buttonStyle(.kx(.primary, fullWidth: true))
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
    }

    private func focusCard(title: String, detail: String, symbol: String, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: KXSpacing.md) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(selected ? KXColor.onAccent : KXColor.inkSecondary)
                .frame(width: 40, height: 40)
                .background(selected ? KXColor.accent : KXColor.surfaceTint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Text(title).font(KXFont.headline).foregroundStyle(KXColor.ink)
                Text(detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? KXColor.accent : KXColor.border)
                .accessibilityHidden(true)
        }
        .kxCard(selected ? .accent : .raised)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview {
    OnboardingWelcomeView()
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}

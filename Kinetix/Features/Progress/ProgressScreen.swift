import SwiftUI

/// Analytics & load. Filled in by Milestone 5 (load model) and 3/4 (PRs, runs).
struct ProgressScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                KXScreenHeader(title: "Analytics Load")
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.largeTitle)
                        .foregroundStyle(KXColor.accent)
                        .accessibilityHidden(true)
                    Text("Training load, personal records and race estimates will appear here once you've logged a few sessions.")
                        .font(KXFont.callout)
                        .foregroundStyle(KXColor.inkSecondary)
                }
                .kxCard(.tinted)
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
    }
}

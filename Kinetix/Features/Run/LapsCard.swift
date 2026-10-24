import SwiftUI
import TrainingEngine

/// Laps marked by hand during a run (watch double tap, crown or Lap button).
struct LapsCard: View {
    let laps: [Lap]
    let format: DisplayFormat

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader("Laps", subtitle: "Marked from your watch")
            HStack {
                Text("Lap").frame(width: 32, alignment: .leading)
                Text("Time").frame(maxWidth: .infinity, alignment: .leading)
                Text("Distance").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Pace").frame(maxWidth: .infinity, alignment: .trailing)
                Text("HR").frame(width: 32, alignment: .trailing)
            }
            .font(KXFont.captionEmphasis)
            .foregroundStyle(KXColor.inkSecondary)
            .accessibilityHidden(true)
            ForEach(laps, id: \.index) { lap in
                HStack {
                    Text("\(lap.index)").font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary)
                        .frame(width: 32, alignment: .leading)
                    Text(Units.formatMinutesSeconds(lap.durationSeconds))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(format.distance(lap.distanceMeters, decimals: 2))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(lap.pace.map { format.pace($0) } ?? "--")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(lap.averageHeartRate.map { "\(Int($0))" } ?? "")
                        .foregroundStyle(KXColor.inkSecondary)
                        .frame(width: 32, alignment: .trailing)
                }
                .font(KXFont.body.monospacedDigit())
                .foregroundStyle(KXColor.ink)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Lap \(lap.index), \(Units.formatMinutesSeconds(lap.durationSeconds)), \(format.distance(lap.distanceMeters, decimals: 2))"
                                    + (lap.pace.map { ", pace \(format.pace($0))" } ?? ""))
            }
        }
        .kxCard()
    }
}

import SwiftUI
import SwiftData
import TrainingEngine

/// A run's headline numbers in one row of big condensed figures: "9.62 km · 4:41 /km · 45:07 · 162".
struct RunStatsGrid: View {
    struct Stat: Identifiable {
        let label: String
        let value: String
        var unit: String?
        var id: String { label }
    }

    let stats: [Stat]

    var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.sm) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    KXOverline(stat.label)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(stat.value)
                            .font(KXFont.number(28, relativeTo: .title2))
                            .foregroundStyle(KXColor.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if let unit = stat.unit {
                            Text(unit)
                                .font(KXFont.caption)
                                .foregroundStyle(KXColor.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The route on top and the headline numbers underneath, in one card.
struct RunHeroCard<Map: View>: View {
    let showsMap: Bool
    let stats: [RunStatsGrid.Stat]
    let secondary: [RunStatsGrid.Stat]
    var footnote: String?
    @ViewBuilder let map: () -> Map

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsMap {
                map()
                    .frame(height: 200)
                    .clipped()
            }
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                RunStatsGrid(stats: stats)
                if !secondary.isEmpty {
                    Divider().overlay(KXColor.border)
                    RunStatsGrid(stats: secondary)
                }
                if let footnote {
                    Text(footnote).font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                }
            }
            .padding(KXSpacing.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .shadow(color: KXShadow.color, radius: KXShadow.radius, y: KXShadow.y)
    }
}

/// Time in each heart-rate zone as one bar, with the share under each zone.
struct HeartRateZonesCard: View {
    let samples: [HeartRateSample]

    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Query(filter: #Predicate<RunLogModel> { $0.isFinished && $0.deletedAt == nil }) private var runs: [RunLogModel]

    static let colors: [Color] = [KXColor.other, KXColor.run, KXColor.success, KXColor.warning, KXColor.danger]

    /// Seconds in zones 1–5 (below zone 1 counts as zone 1).
    private var seconds: [Double] {
        let zones = StrainService.zones(profile: profiles.first?.profile, runs: runs)
        var result = Array(repeating: 0.0, count: 5)
        let sorted = samples.sorted { $0.elapsed < $1.elapsed }
        for (sample, next) in zip(sorted, sorted.dropFirst()) {
            let gap = min(max(next.elapsed - sample.elapsed, 0), 30)
            result[max(zones.zone(for: sample.bpm), 1) - 1] += gap
        }
        return result
    }

    var body: some View {
        let seconds = seconds
        let total = max(seconds.reduce(0, +), 1)
        let hard = (seconds[3] + seconds[4]) / total
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack {
                KXOverline("Heart-rate zones")
                Spacer()
                Text("\(Int((hard * 100).rounded()))% in zones 4–5")
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { zone in
                        if seconds[zone] > 0 {
                            Rectangle()
                                .fill(Self.colors[zone])
                                .frame(width: max(2, (geo.size.width - 8) * seconds[zone] / total))
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            HStack {
                ForEach(0..<5, id: \.self) { zone in
                    HStack(spacing: 3) {
                        Text("Z\(zone + 1)").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                        Text("\(Int((seconds[zone] / total * 100).rounded()))%")
                            .font(KXFont.custom(.semiBold, 12, relativeTo: .caption).monospacedDigit())
                            .foregroundStyle(KXColor.ink)
                    }
                    if zone < 4 { Spacer(minLength: 0) }
                }
            }
        }
        .kxCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart-rate zones")
        .accessibilityValue((0..<5).map { "zone \($0 + 1) \(Int((seconds[$0] / total * 100).rounded())) percent" }.joined(separator: ", "))
    }
}

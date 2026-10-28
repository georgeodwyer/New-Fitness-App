import SwiftUI
import TrainingEngine

/// Predicted 5K, 10K, half and marathon times from current fitness, the goal race highlighted.
struct RacePredictionsCard: View {
    let profile: AthleteProfile

    private struct Race: Identifiable {
        let meters: Double
        let name: String
        var id: String { name }
    }

    private static let races = [Race(meters: 5000, name: "5K"), Race(meters: 10000, name: "10K"),
                                Race(meters: 21097.5, name: "Half"), Race(meters: 42195, name: "Marathon")]

    private var goalMeters: Double? {
        switch profile.goal {
        case .first5k, .faster5k: return 5000
        case .faster10k: return 10000
        case .halfMarathon: return 21097.5
        case .marathon: return 42195
        default: return nil
        }
    }

    var body: some View {
        let zones = PaceZones(profile: profile)
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack {
                KXOverline("Race predictions")
                Spacer()
                Text(profile.recentRace == nil ? "from your experience" : "from your race time")
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: KXSpacing.sm), GridItem(.flexible())], spacing: KXSpacing.sm) {
                ForEach(Self.races) { race in
                    let isGoal = race.meters == goalMeters
                    VStack(alignment: .leading, spacing: 2) {
                        KXOverline(isGoal ? "\(race.name) · goal race" : race.name, color: isGoal ? KXColor.accent : KXColor.inkSecondary)
                        Text(Units.formatMinutesSeconds(zones.predictedTime(distanceMeters: race.meters)))
                            .font(KXFont.number(26, relativeTo: .title2))
                            .foregroundStyle(KXColor.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(KXSpacing.md)
                    .background(isGoal ? KXColor.accentSoft : KXColor.surfaceTint,
                                in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous)
                            .strokeBorder(isGoal ? KXColor.accent.opacity(0.6) : .clear, lineWidth: 1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .kxCard()
        .accessibilityIdentifier("progress.predictions")
    }
}

/// The three most-trained lifts: best estimated 1-rep max per session over the last 12 weeks
/// as a small line, the latest figure and the change.
struct StrengthTrendCard: View {
    let workouts: [StrengthLogModel]
    let units: UnitSystem

    private struct Trend: Identifiable {
        let name: String
        let values: [Double]
        var id: String { name }
    }

    private var format: DisplayFormat { DisplayFormat(units: units) }

    private var trends: [Trend] {
        let since = Calendar.kinetix.date(byAdding: .weekOfYear, value: -12, to: .now) ?? .distantPast
        let sessions = workouts.filter { $0.isFinished && !$0.isSoftDeleted && $0.startedAt >= since }
            .sorted { $0.startedAt < $1.startedAt }
        var series: [String: (name: String, values: [Double])] = [:]
        for session in sessions {
            var best: [String: (String, Double)] = [:]
            for set in session.orderedSets where set.isCompleted && !set.isBodyweight && set.actualWeightKg > 0 && set.actualReps > 0 {
                // Epley: weight × (1 + reps / 30).
                let estimate = set.actualWeightKg * (1 + Double(min(set.actualReps, 12)) / 30)
                if estimate > (best[set.exerciseId]?.1 ?? 0) { best[set.exerciseId] = (set.exerciseName, estimate) }
            }
            for (id, value) in best {
                series[id, default: (name: value.0, values: [])].values.append(value.1)
            }
        }
        return series.values
            .filter { $0.values.count >= 2 }
            .sorted { $0.values.count > $1.values.count }
            .prefix(3)
            .map { Trend(name: $0.name.isEmpty ? "Lift" : $0.name, values: $0.values) }
    }

    var body: some View {
        let trends = trends
        if !trends.isEmpty {
            let colors = [KXColor.lift, KXColor.accent, KXColor.run]
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                HStack {
                    KXOverline("Strength")
                    Spacer()
                    Text("est. 1-rep max · 12 weeks").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
                ForEach(Array(trends.enumerated()), id: \.element.id) { index, trend in
                    if index > 0 { Divider().overlay(KXColor.border) }
                    HStack(spacing: KXSpacing.md) {
                        Text(trend.name)
                            .font(KXFont.bodyEmphasis)
                            .foregroundStyle(KXColor.ink)
                            .lineLimit(2)
                            .frame(width: 96, alignment: .leading)
                        Sparkline(values: trend.values, color: colors[index % colors.count])
                            .frame(height: 30)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(format.weight(trend.values.last ?? 0))
                                .font(KXFont.number(20, relativeTo: .headline))
                                .foregroundStyle(KXColor.ink)
                            let change = (trend.values.last ?? 0) - (trend.values.first ?? 0)
                            Text((change >= 0 ? "+" : "−") + format.weight(abs(change)))
                                .font(KXFont.captionEmphasis)
                                .foregroundStyle(change >= 0 ? KXColor.success : KXColor.warning)
                        }
                        .frame(minWidth: 64, alignment: .trailing)
                    }
                    .padding(.vertical, KXSpacing.xs)
                    .accessibilityElement(children: .combine)
                }
            }
            .kxCard()
            .accessibilityIdentifier("progress.strengthTrend")
        }
    }
}

/// A small line with a soft fill and a dot on the latest value.
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let low = values.min() ?? 0, high = values.max() ?? 1
            let span = max(high - low, 0.0001)
            let points = values.enumerated().map { index, value in
                CGPoint(x: values.count > 1 ? geo.size.width * CGFloat(index) / CGFloat(values.count - 1) : 0,
                        y: geo.size.height - 3 - (geo.size.height - 6) * CGFloat((value - low) / span))
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.3), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle().fill(color).frame(width: 7, height: 7).position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

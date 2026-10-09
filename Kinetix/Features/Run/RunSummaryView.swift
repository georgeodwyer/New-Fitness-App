import SwiftUI
import TrainingEngine

/// After a run: map, totals, time in target pace, heart rate, splits and segment results.
struct RunSummaryView: View {
    let title: String
    let summary: RunSummary
    let units: UnitSystem
    var simulated = false
    let onDone: () -> Void

    private var format: DisplayFormat { DisplayFormat(units: units) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXOverline(simulated ? "Run complete · simulated GPS" : "Run complete", color: KXColor.success)
                    Text(title).font(KXFont.display).foregroundStyle(KXColor.ink)
                }
                if summary.route.count > 1 {
                    RouteMap(route: summary.route)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                }
                totals
                targetCard
                if !summary.splits.isEmpty { splitsCard }
                if summary.segments.contains(where: { $0.segment.kind == .work }) { repsCard }
            }
            .padding(KXSpacing.screenMargin)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Done", action: onDone)
                .buttonStyle(.kx(.primary, fullWidth: true))
                .padding(KXSpacing.screenMargin)
                .background(KXColor.background)
        }
        .background(KXColor.background.ignoresSafeArea())
    }

    private var totals: some View {
        VStack(spacing: KXSpacing.md) {
            HStack {
                KXMetric(label: "Distance", value: Units.formatDistance(meters: summary.distanceMeters, units: units),
                         unit: Units.distanceUnitLabel(units), size: .small)
                Spacer()
                KXMetric(label: "Time", value: Units.formatMinutesSeconds(summary.durationSeconds), size: .small)
                Spacer()
                KXMetric(label: "Avg pace", value: summary.averagePace.map { Units.formatPace($0, units: units) } ?? "--:--",
                         unit: Units.paceUnitLabel(units), size: .small)
            }
            Divider()
            HStack {
                KXMetric(label: "Avg HR", value: summary.averageHeartRate.map { "\(Int($0))" } ?? "--", unit: "bpm", size: .small)
                Spacer()
                KXMetric(label: "Max HR", value: summary.maxHeartRate.map { "\(Int($0))" } ?? "--", unit: "bpm", size: .small)
                Spacer()
                KXMetric(label: "Splits", value: "\(summary.splits.count)", size: .small)
            }
            if summary.averageHeartRate == nil {
                Text("Heart rate appears here once Apple Watch or a chest strap is connected.")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .kxCard()
    }

    private var targetCard: some View {
        HStack(spacing: KXSpacing.lg) {
            KXRingGauge(value: summary.timeInTargetFraction ?? 0,
                        label: summary.timeInTargetFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "--",
                        caption: "on target", tint: KXColor.success)
                .frame(width: 100, height: 100)
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Text("Time in target pace").font(KXFont.headline).foregroundStyle(KXColor.ink)
                Text(summary.targetedSeconds > 0
                     ? "\(Units.formatMinutesSeconds(summary.timeInTargetSeconds)) of \(Units.formatMinutesSeconds(summary.targetedSeconds)) in your target range (main efforts, not warm-up or recoveries)."
                     : "No paced efforts were measured on this run.")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .kxCard()
    }

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader("Splits", subtitle: units == .metric ? "Per kilometre" : "Per mile")
            let fastest = summary.splits.map(\.durationSeconds).min() ?? 0
            let slowest = summary.splits.map(\.durationSeconds).max() ?? 1
            ForEach(summary.splits, id: \.index) { split in
                HStack(spacing: KXSpacing.md) {
                    Text("\(split.index)").font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary).frame(width: 24, alignment: .leading)
                    GeometryReader { geo in
                        // Faster splits draw longer bars.
                        let range = max(slowest - fastest, 1)
                        let fraction = 0.35 + 0.65 * (slowest - split.durationSeconds) / range
                        Capsule().fill(KXColor.accent.opacity(0.85))
                            .frame(width: geo.size.width * fraction, height: 10)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 20)
                    .accessibilityHidden(true)
                    Text(Units.formatMinutesSeconds(split.durationSeconds))
                        .font(KXFont.bodyEmphasis.monospacedDigit()).frame(width: 56, alignment: .trailing)
                    Text(split.averageHeartRate.map { "\(Int($0))" } ?? "")
                        .font(KXFont.caption.monospacedDigit()).foregroundStyle(KXColor.inkSecondary).frame(width: 32, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Split \(split.index), \(Units.formatMinutesSeconds(split.durationSeconds))")
            }
        }
        .kxCard()
    }

    private var repsCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader("Efforts", subtitle: "Actual pace against target")
            ForEach(summary.segments.filter { $0.segment.kind == .work }, id: \.index) { result in
                let onTarget = result.secondsMeasured > 0 && result.secondsInTarget / result.secondsMeasured >= 0.7
                HStack {
                    Image(systemName: onTarget ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(onTarget ? KXColor.success : KXColor.warning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                        Text(result.segment.label ?? "Effort").font(KXFont.bodyEmphasis)
                        Text(result.segment.targetPace.map { "Target \(format.paceRange($0))" } ?? "")
                            .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: KXSpacing.xxs) {
                        Text(result.averagePace.map { format.pace($0) } ?? "--")
                            .font(KXFont.bodyEmphasis.monospacedDigit())
                        Text("\(format.distance(result.distanceMeters, decimals: 2)) · \(Units.formatMinutesSeconds(result.durationSeconds))")
                            .font(KXFont.caption.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard()
    }
}

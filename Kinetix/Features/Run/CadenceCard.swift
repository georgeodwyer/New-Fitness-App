import SwiftUI
import TrainingEngine

/// Cadence (steps per minute) and stride length on a finished run: the averages, a chart
/// through the run and each split. Hidden when the run has no step counts (older runs,
/// imports, simulated GPS).
struct CadenceCard: View {
    let samples: [StepSample]?
    let splits: [Split]
    let units: UnitSystem

    /// "Cadence 172 spm" and "Stride 1.12 m" for the run's headline numbers (none without steps).
    static func stats(samples: [StepSample]?, distanceMeters: Double, durationSeconds: Double, units: UnitSystem) -> [RunStatsGrid.Stat] {
        var stats: [RunStatsGrid.Stat] = []
        if let cadence = RunCadence.averageCadence(samples, durationSeconds: durationSeconds) {
            stats.append(.init(label: "Cadence", value: "\(Int(cadence.rounded()))", unit: "spm"))
        }
        if let stride = RunCadence.averageStride(samples, distanceMeters: distanceMeters, durationSeconds: durationSeconds) {
            let (value, unit) = strideText(stride, units: units)
            stats.append(.init(label: "Stride", value: value, unit: unit))
        }
        return stats
    }

    /// 1.12 m, or 3.7 ft.
    static func strideText(_ meters: Double, units: UnitSystem) -> (String, String) {
        units == .imperial ? (String(format: "%.1f", meters * 3.28084), "ft") : (String(format: "%.2f", meters), "m")
    }

    private var series: [RunChartPoint] { RunCadence.series(samples) }
    private var perSplit: [RunCadence.SplitSteps?] {
        RunCadence.perSplit(splits, samples: samples, splitMeters: units == .metric ? 1000 : Units.metersPerMile)
    }

    var body: some View {
        let points = series
        if points.count >= 3 {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                RunLineChart(title: "Cadence", points: points, kind: .cadence)
                let rows = Array(zip(splits, perSplit)).compactMap { split, steps in steps.map { (split.index, $0) } }
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: KXSpacing.sm) {
                        KXSectionHeader("Cadence and stride", subtitle: units == .metric ? "Per kilometre" : "Per mile")
                        ForEach(rows, id: \.0) { index, steps in
                            let stride = Self.strideText(steps.strideMeters, units: units)
                            HStack(spacing: KXSpacing.md) {
                                Text("\(index)").font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary)
                                    .frame(width: 24, alignment: .leading)
                                Text("\(Int(steps.cadence.rounded())) spm").font(KXFont.bodyEmphasis.monospacedDigit())
                                Spacer()
                                Text("\(stride.0) \(stride.1)").font(KXFont.body.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Text("Cadence is steps per minute; stride is the distance covered by each step. Both are measured by your iPhone or Apple Watch.")
                            .font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .kxCard()
                }
            }
        }
    }
}

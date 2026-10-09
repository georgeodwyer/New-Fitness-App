import SwiftUI
import Charts
import TrainingEngine

// MARK: - Recovery check-in

/// Optional daily check-in: sleep, soreness, energy (1–5). Feeds the balancing logic.
struct CheckInCard: View {
    let existing: RecoveryCheckInModel?
    let onSave: (RecoveryCheckIn) -> Void

    @State private var sleep = 3
    @State private var soreness = 2
    @State private var energy = 3
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            if let existing, !editing {
                let readiness = existing.engineValue.readiness
                HStack(spacing: KXSpacing.lg) {
                    KXRingGauge(value: readiness, label: "\(Int((readiness * 100).rounded()))%", caption: "ready",
                                tint: existing.engineValue.isPoor ? KXColor.warning : KXColor.success, lineWidth: 8)
                        .frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        KXSectionHeader("Today's check-in")
                        Text(existing.engineValue.isPoor
                             ? "You're not fully recovered, so today's plan has been eased where it can be."
                             : "Recovered and ready. Train as planned.")
                            .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Update") {
                            sleep = existing.sleep; soreness = existing.soreness; energy = existing.energy
                            editing = true
                        }
                        .font(KXFont.captionEmphasis)
                        .foregroundStyle(KXColor.accent)
                    }
                }
            } else {
                KXSectionHeader("How are you today?", subtitle: "Optional · helps balance your training")
                ratingRow("Sleep", value: $sleep, low: "Poor", high: "Great", symbol: "moon.zzz")
                ratingRow("Soreness", value: $soreness, low: "None", high: "Very", symbol: "bandage")
                ratingRow("Energy", value: $energy, low: "Drained", high: "Buzzing", symbol: "bolt")
                Button("Save check-in") {
                    onSave(RecoveryCheckIn(sleep: sleep, soreness: soreness, energy: energy))
                    editing = false
                }
                .buttonStyle(.kx(.secondary, fullWidth: true))
            }
        }
        .kxCard()
    }

    private func ratingRow(_ title: String, value: Binding<Int>, low: String, high: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            HStack {
                Label(title, systemImage: symbol).font(KXFont.callout).foregroundStyle(KXColor.ink)
                Spacer()
                Text("\(low) → \(high)").font(.caption2).foregroundStyle(KXColor.inkTertiary)
            }
            HStack(spacing: KXSpacing.xs) {
                ForEach(1...5, id: \.self) { rating in
                    KXSelectableChip(text: "\(rating)", isSelected: value.wrappedValue == rating) { value.wrappedValue = rating }
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(title) \(rating) of 5")
                }
            }
        }
    }
}

// MARK: - Training load hero

/// The acute:chronic ratio as the dashboard's hero figure on a three-zone meter,
/// with running, lifting and combined load tiles.
struct LoadHeroCard: View {
    let report: LoadReport

    private var combined: LoadFigures { report.combined }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            KXSectionHeader("Training load", subtitle: "Session load = minutes × effort, so running and lifting share one scale")
            HStack(alignment: .firstTextBaseline, spacing: KXSpacing.md) {
                Text(combined.ratio.map { String(format: "%.2f", $0) } ?? "–")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(KXColor.ink)
                    .accessibilityLabel("Acute to chronic ratio \(combined.ratio.map { String(format: "%.2f", $0) } ?? "not available yet")")
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Text("Acute : chronic").font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary)
                    KXStatusPill(level: level(combined.status), text: combined.status.title)
                }
            }
            ZoneMeter(ratio: combined.ratio)
            Text(combined.status.advice)
                .font(KXFont.callout)
                .foregroundStyle(KXColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: KXSpacing.sm) {
                LoadTile(title: "Running", figures: report.running, dot: KXColor.run)
                LoadTile(title: "Lifting", figures: report.lifting, dot: KXColor.lift)
                LoadTile(title: "Combined", figures: report.combined, dot: KXColor.ink)
            }
        }
        .kxCard()
    }

    private func level(_ status: LoadStatus) -> KXStatusPill.Level {
        switch status {
        case .building: return .neutral
        case .undertrained: return .low
        case .optimal: return .optimal
        case .high: return .high
        }
    }
}

/// 0–2.0 scale with undertrained / optimal / high-risk zones and a marker.
private struct ZoneMeter: View {
    let ratio: Double?
    private let maxRatio = 2.0

    var body: some View {
        VStack(spacing: KXSpacing.xs) {
            GeometryReader { geo in
                let width = geo.size.width
                let x = { (value: Double) in width * min(max(value, 0), maxRatio) / maxRatio }
                ZStack(alignment: .leading) {
                    // Zones, separated by 2 pt surface gaps.
                    HStack(spacing: 2) {
                        Capsule().fill(KXColor.warning.opacity(0.35)).frame(width: x(0.8) - 2)
                        Rectangle().fill(KXColor.success.opacity(0.4)).frame(width: x(1.3) - x(0.8) - 2)
                        Capsule().fill(KXColor.danger.opacity(0.3))
                    }
                    .frame(height: 10)
                    if let ratio {
                        Circle()
                            .fill(KXColor.ink)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(KXColor.surface, lineWidth: 3))
                            .offset(x: x(ratio) - 9)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 22)
            HStack {
                Text("Under").frame(maxWidth: .infinity, alignment: .leading)
                Text("0.8 – 1.3 optimal").frame(maxWidth: .infinity)
                Text("High").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundStyle(KXColor.inkSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Load ratio meter")
        .accessibilityValue(ratio.map { String(format: "%.2f; optimal is 0.8 to 1.3", $0) } ?? "Building baseline")
    }
}

private struct LoadTile: View {
    let title: String
    let figures: LoadFigures
    let dot: Color

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            HStack(spacing: KXSpacing.xs) {
                Circle().fill(dot).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(title).font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary)
            }
            Text("\(Int(figures.acute.rounded()))")
                .font(KXFont.metricSmall)
                .foregroundStyle(KXColor.ink)
            Text("7 days · 28-day avg \(Int(figures.chronic.rounded()))/wk")
                .font(.caption2)
                .foregroundStyle(KXColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let ratio = figures.ratio {
                Text("Ratio \(String(format: "%.2f", ratio))").font(.caption2.weight(.semibold)).foregroundStyle(KXColor.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KXSpacing.sm)
        .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) load: \(Int(figures.acute)) over 7 days, average \(Int(figures.chronic)) per week over 28 days")
    }
}

// MARK: - Daily load chart

/// Last 28 days of load, running and lifting stacked per day, with tap-to-inspect.
struct DailyLoadChart: View {
    let daily: [DailyLoad]
    @State private var selected: Date?

    private var maxTotal: Double { max(daily.map(\.total).max() ?? 0, 100) }
    /// A 2 pt surface gap between stacked segments, in data units (plot is 150 pt tall).
    private var gap: Double { maxTotal * 1.15 * 2 / 150 }

    private var selectedDay: DailyLoad? {
        guard let selected else { return nil }
        return daily.first { Calendar.kinetix.isDate($0.date, inSameDayAs: selected) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Daily load", subtitle: "Last 28 days")
            HStack(spacing: KXSpacing.lg) {
                legendItem("Running", KXColor.run)
                legendItem("Lifting", KXColor.lift)
                legendItem("Other", KXColor.other)
                Spacer()
            }
            Chart {
                ForEach(daily) { day in
                    if day.running > 0 {
                        BarMark(x: .value("Day", day.date, unit: .day), yStart: .value("Load", 0), yEnd: .value("Load", day.running), width: .fixed(7))
                            .foregroundStyle(KXColor.run)
                            .cornerRadius(3)
                    }
                    if day.lifting > 0 {
                        let start = day.running > 0 ? day.running + gap : 0
                        BarMark(x: .value("Day", day.date, unit: .day), yStart: .value("Load", start), yEnd: .value("Load", start + day.lifting), width: .fixed(7))
                            .foregroundStyle(KXColor.lift)
                            .cornerRadius(3)
                    }
                    if day.other > 0 {
                        let start = (day.running > 0 ? day.running + gap : 0) + (day.lifting > 0 ? day.lifting + gap : 0)
                        BarMark(x: .value("Day", day.date, unit: .day), yStart: .value("Load", start), yEnd: .value("Load", start + day.other), width: .fixed(7))
                            .foregroundStyle(KXColor.other)
                            .cornerRadius(3)
                    }
                }
                if let day = selectedDay {
                    RuleMark(x: .value("Day", day.date, unit: .day))
                        .foregroundStyle(KXColor.inkTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            tooltip(day)
                        }
                }
            }
            .chartYScale(domain: 0...(maxTotal * 1.15))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(KXColor.inkSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(KXColor.border)
                    AxisValueLabel().foregroundStyle(KXColor.inkSecondary)
                }
            }
            .chartXSelection(value: $selected)
            .frame(height: 190)
            .accessibilityLabel("Daily training load, last 28 days")
            if daily.allSatisfy({ $0.total == 0 }) {
                Text("Complete a run or lift to see your load build up here.")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
            } else {
                Text("Touch and drag across the chart to see each day.")
                    .font(.caption2).foregroundStyle(KXColor.inkTertiary)
            }
        }
        .kxCard()
    }

    private func legendItem(_ title: String, _ color: Color) -> some View {
        HStack(spacing: KXSpacing.xs) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func tooltip(_ day: DailyLoad) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.date.formatted(.dateTime.weekday(.abbreviated).day().month())).font(.caption2.weight(.semibold))
            Text("Running \(Int(day.running)) · Lifting \(Int(day.lifting))\(day.other > 0 ? " · Other \(Int(day.other))" : "")")
                .font(.caption2.monospacedDigit())
            Text("Total \(Int(day.total)) AU").font(.caption2.weight(.semibold))
        }
        .foregroundStyle(KXColor.ink)
        .padding(KXSpacing.sm)
        .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.sm))
        .shadow(color: KXShadow.color, radius: 6, y: 2)
    }
}

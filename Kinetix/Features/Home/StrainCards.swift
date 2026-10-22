import SwiftUI
import Charts
import TrainingEngine

// MARK: - Strain and recovery

/// Today's strain (0–21) against its target band, recovery, legs and this week vs usual.
struct StrainCard: View {
    let report: StrainReport
    /// Last night's Health data isn't in yet, so there's no recovery score.
    var isWaitingForLastNight = false

    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 132

    private var strain: Double { report.today.strain }
    private var target: StrainTarget { report.target }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            KXSectionHeader("Exertion", subtitle: "Today's target \(format(target.low))–\(format(target.high)) of 21")
            HStack(alignment: .center, spacing: KXSpacing.lg) {
                StrainRing(strain: strain, target: target)
                    .frame(width: ringSize, height: ringSize)
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    recovery
                    legs
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(statusText + " " + target.reason)
                .font(KXFont.callout)
                .foregroundStyle(KXColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !report.today.activities.isEmpty { activities }
            WeekVsUsualBar(ratio: report.weekVsUsual)
        }
        .kxCard()
        .accessibilityIdentifier("dashboard.exertion")
    }

    private var statusText: String {
        if strain > target.high { return "Above today's target: take the rest of the day easy." }
        if strain >= target.low { return "You're in today's target range." }
        return "\(format(target.low - strain)) to go to reach today's target."
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            KXOverline("Recovery")
            if let recovery = report.recovery {
                HStack(alignment: .firstTextBaseline, spacing: KXSpacing.xs) {
                    Text("\(Int(recovery.score))%")
                        .font(KXFont.metricSmall)
                        .foregroundStyle(KXColor.ink)
                    Text(recovery.band.title)
                        .font(KXFont.captionEmphasis)
                        .foregroundStyle(color(recovery.band))
                }
                Text(recovery.parts.map(\.name).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(KXColor.inkTertiary)
            } else {
                Text(waitingText)
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var waitingText: String {
        isWaitingForLastNight
            ? "Waiting for last night's sleep from Apple Health. Pull down to refresh."
            : "Add your score, or connect Apple Health, to see it."
    }

    private var legs: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            KXOverline("Legs")
            KXStatusPill(level: legsLevel, text: report.legs.status.title)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(report.legs.status.advice)
    }

    private var legsLevel: KXStatusPill.Level {
        switch report.legs.status {
        case .fresh: return .optimal
        case .ok: return .neutral
        case .tired: return .high
        }
    }

    private var activities: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            ForEach(report.today.activities) { activity in
                HStack {
                    Image(systemName: symbol(activity.source))
                        .foregroundStyle(KXColor.inkSecondary)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(activity.name).font(KXFont.callout).foregroundStyle(KXColor.ink)
                    if activity.usedHeartRate {
                        Image(systemName: "heart.fill").font(.caption2).foregroundStyle(KXColor.danger)
                            .accessibilityLabel("from heart rate")
                    }
                    Spacer()
                    Text("+\(format(Strain.strain(load: activity.load)))")
                        .font(KXFont.captionEmphasis.monospacedDigit())
                        .foregroundStyle(KXColor.inkSecondary)
                }
            }
            Text("Exertion isn't additive: each point takes more than the last, so the day's total is less than the sum.")
                .font(.caption2)
                .foregroundStyle(KXColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func symbol(_ source: StrainActivity.Source) -> String {
        switch source {
        case .run: return "figure.run"
        case .lift: return "dumbbell"
        case .other: return "figure.mixed.cardio"
        case .steps: return "figure.walk"
        }
    }

    private func color(_ band: RecoveryScore.Band) -> Color {
        switch band {
        case .low: return KXColor.danger
        case .medium: return KXColor.warning
        case .high: return KXColor.success
        }
    }

    private func format(_ value: Double) -> String { String(format: "%.1f", max(0, value)) }
}

/// A 0–21 ring: today's strain over a faint target band.
struct StrainRing: View {
    let strain: Double
    let target: StrainTarget
    var lineWidth: CGFloat = 12

    private func share(_ value: Double) -> Double { min(max(value / Strain.maximum, 0), 1) }

    var body: some View {
        ZStack {
            Circle().stroke(KXColor.border, lineWidth: lineWidth)
            Circle()
                .trim(from: share(target.low), to: share(target.high))
                .stroke(KXColor.accent.opacity(0.25), style: StrokeStyle(lineWidth: lineWidth + 6, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: 0, to: share(strain))
                .stroke(strain > target.high ? KXColor.warning : KXColor.accent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(String(format: "%.1f", strain))
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(KXColor.ink)
                Text("of 21").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exertion \(String(format: "%.1f", strain)) of 21")
        .accessibilityValue("Target \(String(format: "%.1f", target.low)) to \(String(format: "%.1f", target.high))")
    }
}

/// "This week: 112% of your usual" on a 0–200% bar with the normal range marked.
struct WeekVsUsualBar: View {
    let ratio: Double?

    private var normal: ClosedRange<Double> { LoadStatus.optimalRange }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            HStack {
                Text("This week vs your usual").font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary)
                Spacer()
                Text(ratio.map { "\(Int(($0 * 100).rounded()))%" } ?? "After 2 weeks")
                    .font(KXFont.captionEmphasis.monospacedDigit())
                    .foregroundStyle(KXColor.ink)
            }
            GeometryReader { geo in
                let width = geo.size.width
                let x = { (value: Double) in width * min(max(value, 0), 2) / 2 }
                ZStack(alignment: .leading) {
                    Capsule().fill(KXColor.border).frame(height: 8)
                    Rectangle().fill(KXColor.success.opacity(0.35))
                        .frame(width: x(normal.upperBound) - x(normal.lowerBound), height: 8)
                        .offset(x: x(normal.lowerBound))
                    if let ratio {
                        Capsule().fill(ratio > normal.upperBound ? KXColor.warning : KXColor.ink)
                            .frame(width: max(8, x(ratio)), height: 8)
                    }
                }
            }
            .frame(height: 8)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(KXColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        guard let ratio else { return "Your last 7 days against an average week of the last 4, once there's two weeks of training." }
        if ratio > normal.upperBound { return "A big jump on your usual week. Upcoming sessions are eased to keep you healthy." }
        if ratio < normal.lowerBound { return "Lighter than usual: fine for a recovery week." }
        return "Green is a normal week (\(Int(normal.lowerBound * 100))–\(Int(normal.upperBound * 100))% of your usual)."
    }
}

// MARK: - Daily strain chart

/// Strain per day for the last week or month, with today's target marked.
struct DailyStrainChart: View {
    let days: [DayStrain]
    var target: StrainTarget?
    @State private var selected: Date?
    @AppStorage("dashboard.loadRange") private var range = 30

    private var shown: [DayStrain] { Array(days.suffix(range)) }
    private var isWeek: Bool { range == 7 }

    private var selectedDay: DayStrain? {
        guard let selected else { return nil }
        return shown.first { Calendar.kinetix.isDate($0.date, inSameDayAs: selected) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                KXSectionHeader("Daily exertion", subtitle: isWeek ? "Last 7 days" : "Last 30 days")
                Spacer()
                Picker("Period", selection: $range) {
                    Text("Week").tag(7)
                    Text("Month").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .accessibilityIdentifier("dashboard.loadRange")
            }
            Chart {
                ForEach(shown) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Exertion", day.strain), width: .fixed(isWeek ? 22 : 7))
                        .foregroundStyle(Calendar.kinetix.isDateInToday(day.date) ? KXColor.accent : KXColor.ink.opacity(0.7))
                        .cornerRadius(3)
                }
                if let target {
                    ForEach([target.low, target.high], id: \.self) { value in
                        RuleMark(y: .value("Target", value))
                            .foregroundStyle(KXColor.accent.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                if let day = selectedDay {
                    RuleMark(x: .value("Day", day.date, unit: .day))
                        .foregroundStyle(KXColor.inkTertiary)
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            tooltip(day)
                        }
                }
            }
            .chartYScale(domain: 0...21)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 7, 14, 21]) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(KXColor.border)
                    AxisValueLabel().foregroundStyle(KXColor.inkSecondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: isWeek ? 1 : 7)) { _ in
                    AxisValueLabel(format: isWeek ? .dateTime.weekday(.abbreviated) : .dateTime.day().month(.abbreviated))
                        .foregroundStyle(KXColor.inkSecondary)
                }
            }
            .chartXSelection(value: $selected)
            .frame(height: 190)
            .accessibilityLabel("Daily exertion, last \(range) days")
            Text(target == nil ? "Touch and drag across the chart to see each day." : "The dashed lines are today's target. Touch and drag to see each day.")
                .font(.caption2).foregroundStyle(KXColor.inkTertiary)
        }
        .kxCard()
    }

    private func tooltip(_ day: DayStrain) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.date.formatted(.dateTime.weekday(.abbreviated).day().month())).font(.caption2.weight(.semibold))
            Text("Exertion \(String(format: "%.1f", day.strain))").font(.caption2.weight(.semibold))
            ForEach(day.activities.prefix(4)) { activity in
                Text(activity.name).font(.caption2)
            }
        }
        .foregroundStyle(KXColor.ink)
        .padding(KXSpacing.sm)
        .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.sm))
        .shadow(color: KXShadow.color, radius: 6, y: 2)
    }
}

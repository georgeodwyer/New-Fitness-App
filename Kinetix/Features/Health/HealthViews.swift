import SwiftUI
import Charts
import TrainingEngine

// MARK: - Dashboard card

/// Dashboard "Body" card: a tile per Apple Health metric with today's value against usual.
struct BodyCard: View {
    @State private var health = HealthService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                KXOverline(health.isConnected ? "Body · Apple Health" : "Body")
                Spacer()
                if health.isConnected && !health.trends.isEmpty {
                    NavigationLink {
                        ScrollView {
                            HealthProgressView().padding(KXSpacing.screenMargin)
                        }
                        .background(KXColor.background.ignoresSafeArea())
                        .navigationTitle("Body trends")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Text("Trends").font(KXFont.captionEmphasis).foregroundStyle(KXColor.accent)
                    }
                    .accessibilityIdentifier("body.trends")
                }
            }
            HealthStatusContent(compact: true)
            if health.isConnected {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: KXSpacing.sm), GridItem(.flexible(), spacing: KXSpacing.sm)],
                          spacing: KXSpacing.sm) {
                    ForEach(health.trends, id: \.metric) { trend in
                        NavigationLink {
                            HealthMetricDetailView(metric: trend.metric)
                        } label: {
                            HealthTile(trend: trend)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("body.tile.\(trend.metric.rawValue)")
                    }
                }
            }
        }
        .kxCard()
    }
}

/// Connect / permission / no-data messages shared by the dashboard card and Progress tab.
struct HealthStatusContent: View {
    var compact = false
    @State private var health = HealthService.shared
    @State private var working = false

    var body: some View {
        if !health.isAvailable {
            Text("Apple Health isn't available on this device.")
                .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
        } else if !health.isConnected {
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                Text("See resting heart rate, HRV, sleep, steps and more from your iPhone, Apple Watch or any wearable that writes to Apple Health (such as Whoop or Garmin).")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink {
                    AppleHealthView()
                } label: {
                    Label("Connect Apple Health", systemImage: "heart.text.square")
                }
                .buttonStyle(.kx(.secondary, fullWidth: true))
                .accessibilityIdentifier("body.connect")
            }
        } else {
            if health.needsPermission {
                Button {
                    Task {
                        working = true
                        try? await health.requestAuthorization()
                        await health.refresh(force: true)
                        working = false
                    }
                } label: {
                    Label(working ? "Asking…" : "Allow Kinetix to read your body data", systemImage: "hand.raised")
                }
                .buttonStyle(.kx(.secondary, fullWidth: true))
                .disabled(working)
                .accessibilityIdentifier("body.allow")
            }
            if health.trends.isEmpty && !health.needsPermission {
                Text(compact ? "No readings yet. Wear your watch overnight, or check Kinetix is allowed to read this data in the Health app (profile, Apps, Kinetix)."
                             : "No readings in the last 30 days. Kinetix shows whatever your phone and wearables save to Apple Health. If you expected data, check Kinetix is allowed to read it in the Health app: tap your profile, then Apps, then Kinetix.")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One metric: value, unit and how it compares with usual.
struct HealthTile: View {
    let trend: HealthTrend
    @State private var health = HealthService.shared

    /// The last week of readings, for the small line.
    private var recent: [Double] {
        Array((health.metricDays[trend.metric] ?? []).sorted { $0.date < $1.date }.suffix(7).map(\.value))
    }

    var body: some View {
        // Every tile the same size, the same layout: name, then the number with its line, then
        // the comparison (so long names never run into the line).
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            KXOverline(trend.metric.displayName)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(trend.metric.format(trend.latest.value))
                    .font(KXFont.metricSmall)
                    .foregroundStyle(KXColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if trend.metric != .sleep {
                    Text(trend.metric.unit).font(KXFont.caption2).foregroundStyle(KXColor.inkSecondary).lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: KXSpacing.xs)
            }
            .overlay(alignment: .topTrailing) {
                if recent.count >= 3 {
                    Sparkline(values: recent, color: KXColor.run)
                        .frame(width: 44, height: 18)
                        .offset(y: -2)
                }
            }
            Spacer(minLength: 0)
            TrendBadge(trend: trend)
        }
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .topLeading)
        .padding(KXSpacing.md)
        .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Arrow plus "6% above your usual", coloured by whether that's good (always with an icon).
struct TrendBadge: View {
    let trend: HealthTrend

    var body: some View {
        if let text = trend.comparisonText {
            Label {
                Text(text).foregroundStyle(KXColor.ink)
            } icon: {
                Image(systemName: symbol).foregroundStyle(color)
            }
            .font(KXFont.caption2)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(Self.dateText(trend.latest.date)).font(KXFont.caption2).foregroundStyle(KXColor.inkTertiary)
        }
    }

    private var symbol: String {
        switch trend.direction {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .steady: return "equal"
        }
    }

    private var color: Color {
        switch trend.isGoodChange {
        case true?: return KXColor.success
        case false?: return KXColor.warning
        case nil: return KXColor.inkSecondary
        }
    }

    static func dateText(_ date: Date) -> String {
        Calendar.kinetix.isDateInToday(date) ? "Today" : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

// MARK: - Detail

/// A metric over 7 or 30 days, with averages, usual and what it means.
struct HealthMetricDetailView: View {
    let metric: HealthMetric
    @State private var health = HealthService.shared
    @AppStorage("health.range") private var range = 30

    private var days: [HealthDay] { health.metricDays[metric] ?? [] }
    private var trend: HealthTrend? { HealthTrend.make(metric: metric, days: days, calendar: .kinetix) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                if let trend {
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        KXOverline(TrendBadge.dateText(trend.latest.date), color: KXColor.accent)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(metric.format(trend.latest.value)).font(KXFont.metric).foregroundStyle(KXColor.ink)
                            if metric != .sleep { Text(metric.unit).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary) }
                        }
                        TrendBadge(trend: trend)
                    }
                    Picker("Range", selection: $range) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("health.range")
                    HealthChart(metric: metric, days: HealthSeries.window(days, lastDays: range, endingOn: .now, calendar: .kinetix),
                                usual: trend.usual, height: 220)
                        .kxCard()
                    HStack(spacing: KXSpacing.md) {
                        stat("7-day avg", trend.average7)
                        stat("30-day avg", trend.average30)
                        stat("Your usual", trend.usual)
                    }
                } else {
                    HealthStatusContent()
                }
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    KXSectionHeader("What it means")
                    Text(metric.explanation).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if metric == .hrv || metric == .restingHeartRate {
                        Label("Kinetix eases your plan when this is well off your usual and your score isn't great either.",
                              systemImage: "arrow.triangle.branch")
                            .font(KXFont.caption).foregroundStyle(KXColor.ink)
                    }
                    if metric == .sleep {
                        Label("Last night's sleep suggests the sleep rating in your score.", systemImage: "sun.horizon")
                            .font(KXFont.caption).foregroundStyle(KXColor.ink)
                    }
                    Text("General information, not medical advice. If a number worries you, talk to a doctor.")
                        .font(KXFont.caption2).foregroundStyle(KXColor.inkTertiary)
                }
                .kxCard()
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle(metric.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await health.refresh() }
    }

    private func stat(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            Text(value.map { metric.format($0) } ?? "–").font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Bars for daily totals, a line for readings; a dashed line at the person's usual.
struct HealthChart: View {
    let metric: HealthMetric
    let days: [HealthDay]
    let usual: Double?
    var height: CGFloat = 160
    @State private var selected: Date?

    private var selectedDay: HealthDay? {
        guard let selected else { return nil }
        return days.first { Calendar.kinetix.isDate($0.date, inSameDayAs: selected) }
    }

    private var tint: Color {
        switch metric {
        case .restingHeartRate, .hrv: return KXColor.danger
        case .sleep: return KXColor.teal
        case .steps, .activeEnergy: return KXColor.run
        case .vo2Max, .respiratoryRate: return KXColor.lift
        }
    }

    var body: some View {
        if days.isEmpty {
            Text("No readings in this period.").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: height / 2)
        } else {
            Chart {
                ForEach(days, id: \.date) { day in
                    if metric.isDailyTotal {
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value(metric.displayName, day.value))
                            .foregroundStyle(tint)
                            .cornerRadius(3)
                    } else {
                        LineMark(x: .value("Day", day.date, unit: .day), y: .value(metric.displayName, day.value))
                            .foregroundStyle(tint)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Day", day.date, unit: .day), y: .value(metric.displayName, day.value))
                            .foregroundStyle(tint)
                            .symbolSize(days.count > 10 ? 12 : 30)
                    }
                }
                if let usual {
                    RuleMark(y: .value("Usual", usual))
                        .foregroundStyle(KXColor.inkTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Usual").font(KXFont.caption2).foregroundStyle(KXColor.inkSecondary)
                        }
                }
                if let day = selectedDay {
                    RuleMark(x: .value("Day", day.date, unit: .day))
                        .foregroundStyle(KXColor.inkTertiary)
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            VStack(spacing: 0) {
                                Text(metric.format(day.value) + (metric == .sleep ? "" : " \(metric.unit)"))
                                    .font(KXFont.captionEmphasis).foregroundStyle(KXColor.ink)
                                Text(day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                    .font(KXFont.caption2).foregroundStyle(KXColor.inkSecondary)
                            }
                            .padding(KXSpacing.xs)
                            .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.sm))
                        }
                }
            }
            .chartXSelection(value: $selected)
            .chartXScale(range: .plotDimension(startPadding: 4, endPadding: days.count > 10 ? 14 : 4))
            .chartYScale(domain: .automatic(includesZero: metric.isDailyTotal))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: days.count > 10 ? 7 : 1)) { _ in
                    AxisValueLabel(format: days.count > 10 ? .dateTime.day().month(.abbreviated) : .dateTime.weekday(.narrow), centered: true)
                        .foregroundStyle(KXColor.inkSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(KXColor.border)
                    AxisValueLabel().foregroundStyle(KXColor.inkSecondary)
                }
            }
            .frame(height: height)
            .accessibilityLabel("\(metric.displayName) chart")
            .accessibilityValue(days.map { "\($0.date.formatted(.dateTime.weekday(.wide))): \(metric.format($0.value))" }.joined(separator: ", "))
        }
    }
}

// MARK: - Progress tab

/// Progress → Health: every metric with a chart, 7 or 30 days.
struct HealthProgressView: View {
    @State private var health = HealthService.shared
    @AppStorage("health.range") private var range = 30

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xl) {
            HealthStatusContent()
            if health.isConnected && !health.trends.isEmpty {
                Picker("Range", selection: $range) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("health.range")
                ForEach(health.trends, id: \.metric) { trend in
                    NavigationLink {
                        HealthMetricDetailView(metric: trend.metric)
                    } label: {
                        VStack(alignment: .leading, spacing: KXSpacing.sm) {
                            HStack(alignment: .firstTextBaseline) {
                                Label(trend.metric.displayName, systemImage: trend.metric.symbol)
                                    .font(KXFont.headline).foregroundStyle(KXColor.ink)
                                Spacer()
                                Text(trend.metric.format(trend.latest.value) + (trend.metric == .sleep ? "" : " \(trend.metric.unit)"))
                                    .font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
                                Image(systemName: "chevron.right").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                                    .accessibilityHidden(true)
                            }
                            TrendBadge(trend: trend)
                            HealthChart(metric: trend.metric,
                                        days: HealthSeries.window(health.metricDays[trend.metric] ?? [], lastDays: range,
                                                                  endingOn: .now, calendar: .kinetix),
                                        usual: trend.usual)
                                .allowsHitTesting(false)
                        }
                        .kxCard()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("health.card.\(trend.metric.rawValue)")
                }
                Text("Readings come from Apple Health and stay on this phone. General information, not medical advice.")
                    .font(KXFont.caption2).foregroundStyle(KXColor.inkTertiary)
            }
        }
        .task { await health.refresh() }
    }
}

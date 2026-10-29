import SwiftUI
import SwiftData
import Charts
import TrainingEngine

/// The first page of Progress: this week in numbers, recovery over the last 30 days,
/// daily exertion and this week against your usual, with links to the detail sections.
struct ProgressSummaryView: View {
    let units: UnitSystem
    let runs: [RunLogModel]
    let workouts: [StrengthLogModel]
    let profile: AthleteProfile?
    let open: (ProgressScreen.Section) -> Void

    @Query(sort: \RecoveryCheckInModel.date) private var checkIns: [RecoveryCheckInModel]
    @State private var health = HealthService.shared
    @State private var integrations = IntegrationSettings.shared
    @State private var selectedRecoveryDate: Date?

    private var format: DisplayFormat { DisplayFormat(units: units) }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xl) {
            thisWeek
            if let profile { RacePredictionsCard(profile: profile) }
            if health.isConnected { recoveryCard }
            StrengthTrendCard(workouts: workouts, units: units)
            let strain = StrainService.report(sessions: [], runs: runs, lifts: workouts, checkIn: nil, profile: profile,
                                              external: integrations.loadWorkouts, health: HealthInputs.current)
            DailyStrainChart(days: strain.days)
            LoadTrendCard(report: LoadModel.report(
                entries: DashboardService.loadEntries(runs: runs, lifts: workouts, external: integrations.loadWorkouts),
                today: .now, calendar: .kinetix))
            links
        }
    }

    // MARK: This week

    private var weekStart: Date {
        Calendar.kinetix.dateInterval(of: .weekOfYear, for: .now)?.start ?? Calendar.kinetix.startOfDay(for: .now)
    }

    private var thisWeek: some View {
        let start = weekStart
        let weekRuns = runs.filter { $0.countsTowardsHistory && $0.startedAt >= start }
        let weekLifts = workouts.filter { $0.isFinished && !$0.isSoftDeleted && $0.startedAt >= start }
        let meters = weekRuns.map(\.distanceMeters).reduce(0, +)
        let seconds = weekRuns.map(\.durationSeconds).reduce(0, +) + weekLifts.map(\.durationSeconds).reduce(0, +)
        let volume = weekLifts.map(\.volumeKg).reduce(0, +)
        return VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("This week")
            HStack(alignment: .top) {
                KXMetric(label: "Running", value: format.distance(meters), detail: "\(weekRuns.count) run\(weekRuns.count == 1 ? "" : "s")", size: .small)
                Spacer()
                KXMetric(label: "Gym", value: "\(weekLifts.count)", detail: volume > 0 ? format.volume(volume) : "sessions", size: .small)
                Spacer()
                KXMetric(label: "Time", value: Self.hours(seconds), detail: "training", size: .small)
            }
        }
        .kxCard()
        .accessibilityIdentifier("progress.thisWeek")
    }

    private static func hours(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    // MARK: Recovery

    private var recoveryDays: [HealthDay] {
        let calendar = Calendar.kinetix
        let logged = Dictionary(checkIns.filter { !$0.isSoftDeleted }.map { (calendar.startOfDay(for: $0.date), $0.engineValue) },
                                uniquingKeysWith: { _, last in last })
        var days = RecoveryHistory.days(hrv: health.metricDays[.hrv] ?? [], restingHeartRate: health.metricDays[.restingHeartRate] ?? [],
                                        sleep: health.metricDays[.sleep] ?? [], checkIns: logged, lastDays: 30,
                                        endingOn: .now, calendar: calendar)
        // Today only once last night's data is in (as on Today).
        if health.isWaitingForLastNight { days.removeAll { calendar.isDateInToday($0.date) } }
        return days
    }

    private var recoveryCard: some View {
        let days = recoveryDays
        let average = days.isEmpty ? nil : days.map(\.value).reduce(0, +) / Double(days.count)
        return VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Recovery", subtitle: average.map { "Last 30 days · average \(Int($0.rounded()))" } ?? "Last 30 days")
            if days.count < 3 {
                Text("This builds up as Apple Health records your sleep, HRV and resting heart rate.")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let selected = selectedRecoveryDate.flatMap { date in
                    days.first { Calendar.kinetix.isDate($0.date, inSameDayAs: date) }
                }
                Chart {
                    ForEach(days, id: \.date) { day in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Recovery", day.value))
                            .foregroundStyle(TodayFormat.color(RecoveryScore(score: day.value, parts: []).band))
                            .cornerRadius(2)
                            .opacity(selected == nil || selected?.date == day.date ? 1 : 0.4)
                    }
                    if let selected {
                        RuleMark(x: .value("Day", selected.date, unit: .day))
                            .foregroundStyle(KXColor.inkTertiary.opacity(0.6))
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                VStack(spacing: 0) {
                                    Text("\(Int(selected.value.rounded()))").font(KXFont.number(20)).foregroundStyle(KXColor.ink)
                                    Text(selected.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                        .font(KXFont.caption2).foregroundStyle(KXColor.inkSecondary)
                                }
                                .padding(KXSpacing.xs)
                                .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.sm))
                            }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [50, 70, 85]) { _ in
                        AxisGridLine().foregroundStyle(KXColor.border)
                        AxisValueLabel().foregroundStyle(KXColor.inkSecondary)
                    }
                }
                .chartXAxis {
                    // Labels inside the chart's width, so the last date isn't cut off.
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true,
                                       collisionResolution: .greedy(minimumSpacing: 4))
                            .foregroundStyle(KXColor.inkSecondary)
                    }
                }
                .chartXScale(range: .plotDimension(startPadding: 4, endPadding: 18))
                .chartXSelection(value: $selectedRecoveryDate)
                .padding(.top, KXSpacing.lg)
                .frame(height: 170)
                .accessibilityLabel("Recovery over the last 30 days")
                .accessibilityValue(average.map { "Average \(Int($0.rounded()))" } ?? "")
                Text("Touch and drag across the chart to see each day's score.")
                    .font(KXFont.caption2).foregroundStyle(KXColor.inkTertiary)
                HStack(spacing: KXSpacing.lg) {
                    key(KXColor.success, "Good 70+")
                    key(KXColor.warning, "Fair 50–69")
                    key(KXColor.danger, "Low")
                    Spacer()
                }
            }
        }
        .kxCard()
        .accessibilityIdentifier("progress.recovery")
    }

    private func key(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
        }
    }

    // MARK: Links

    private var links: some View {
        VStack(spacing: 0) {
            link("Running", detail: "Best efforts and every run", symbol: "figure.run", tint: KXColor.run, section: .running)
            Divider().padding(.leading, 52)
            link("Strength", detail: "Lifts, records and every session", symbol: "dumbbell.fill", tint: KXColor.lift, section: .strength)
            Divider().padding(.leading, 52)
            link("Health", detail: "HRV, resting heart rate, sleep and more", symbol: "heart.fill", tint: KXColor.danger, section: .health)
        }
        .kxCard(padding: KXSpacing.md)
    }

    private func link(_ title: String, detail: String, symbol: String, tint: Color, section: ProgressScreen.Section) -> some View {
        Button { open(section) } label: {
            HStack(spacing: KXSpacing.md) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                    Text(detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
            }
            .padding(.vertical, KXSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

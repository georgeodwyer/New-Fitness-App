import SwiftUI
import SwiftData
import Charts
import TrainingEngine

/// Stats → Overview's exertion and recovery: recovery over the last 30 days, daily exertion and
/// this week against your usual.
struct ProgressSummaryView: View {
    let units: UnitSystem
    let runs: [RunLogModel]
    let workouts: [StrengthLogModel]
    let profile: AthleteProfile?

    @Query(sort: \RecoveryCheckInModel.date) private var checkIns: [RecoveryCheckInModel]
    @State private var health = HealthService.shared
    @State private var integrations = IntegrationSettings.shared
    @State private var selectedRecoveryDate: Date?

    private var format: DisplayFormat { DisplayFormat(units: units) }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xl) {
            if health.isConnected { recoveryCard }
            let strain = StrainService.report(sessions: [], runs: runs, lifts: workouts, checkIn: nil, profile: profile,
                                              external: integrations.loadWorkouts, health: HealthInputs.current)
            DailyStrainChart(days: strain.days)
            LoadTrendCard(report: LoadModel.report(
                entries: DashboardService.loadEntries(runs: runs, lifts: workouts, external: integrations.loadWorkouts),
                today: .now, calendar: .kinetix))
        }
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

}

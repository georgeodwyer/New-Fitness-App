import SwiftUI
import SwiftData
import Charts
import TrainingEngine

/// Statistics: totals for a period, a calendar of training days, weekly volume, average runs a
/// week, running trends (pace by run type, cadence), strength trends (sets by muscle group,
/// estimated 1-rep max) and best efforts.
struct StatisticsView: View {
    let units: UnitSystem
    let runs: [RunLogModel]
    let workouts: [StrengthLogModel]
    let external: [ExternalWorkout]
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]

    enum Period: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", year = "Year", all = "All time"
        var id: String { rawValue }
    }
    @State private var period: Period = .month

    private var format: DisplayFormat { DisplayFormat(units: units) }

    var body: some View {
        let activities = ActivityRecords.make(runs: runs, lifts: workouts, external: external)
        let calendar = Calendar.kinetix
        VStack(alignment: .leading, spacing: KXSpacing.xl) {
            totalsCard(activities, calendar: calendar)
            HeatmapCard(days: TrainingStats.heatmap(activities, days: 26 * 7, now: .now, calendar: calendar))
            weeklyCards(activities, calendar: calendar)
            runningTrends(activities, calendar: calendar)
            strengthTrends(calendar: calendar)
            BestEffortsCard(units: units)
            if let profile = profiles.first?.profile { RacePredictionsCard(profile: profile) }
        }
    }

    // MARK: Totals

    private func range(_ period: Period, calendar: Calendar) -> (Date, Date) {
        let now = Date.now
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        switch period {
        case .week: return (calendar.startOfISOWeek(for: now), end)
        case .month: return (calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now, end)
        case .year: return (calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now, end)
        case .all: return (.distantPast, end)
        }
    }

    private func totalsCard(_ activities: [ActivityRecord], calendar: Calendar) -> some View {
        let (from, to) = range(period, calendar: calendar)
        let totals = TrainingStats.totals(activities, from: from, to: to)
        let average = TrainingStats.averageRunsPerWeek(activities, weeks: 12, now: .now, calendar: calendar)
        return VStack(alignment: .leading, spacing: KXSpacing.md) {
            Picker("Period", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: KXSpacing.sm), GridItem(.flexible())], spacing: KXSpacing.sm) {
                tile("Distance", format.distance(totals.runMeters, decimals: totals.runMeters >= 100_000 ? 0 : 1))
                tile("Time", hours(totals.seconds))
                tile("Runs", "\(totals.runs)")
                tile("Gym sessions", "\(totals.gymSessions)")
                tile("Gym sets", "\(totals.gymSets)")
                tile("Runs a week", String(format: "%.1f", average), note: "last 12 weeks")
            }
        }
        .kxCard()
    }

    private func hours(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    private func tile(_ label: String, _ value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            KXOverline(label)
            Text(value).font(KXFont.number(24, relativeTo: .title3)).foregroundStyle(KXColor.ink).lineLimit(1).minimumScaleFactor(0.7)
            if let note { Text(note).font(KXFont.caption2).foregroundStyle(KXColor.inkTertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KXSpacing.sm)
        .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Weekly volume

    private func weeklyCards(_ activities: [ActivityRecord], calendar: Calendar) -> some View {
        let weeks = TrainingStats.weekly(activities, weeks: 12, now: .now, calendar: calendar)
        return VStack(alignment: .leading, spacing: KXSpacing.xl) {
            WeeklyBarChart(title: "Weekly distance", weeks: weeks.map { WeeklyTotal(weekStart: $0.start, actual: $0.totals.runMeters) },
                           unitLabel: Units.distanceUnitLabel(units), seriesName: "Run", color: KXColor.run,
                           valueFormatter: { format.distance($0) }, scale: { Units.distance(meters: $0, in: units) })
            WeeklyBarChart(title: "Weekly gym sets", weeks: weeks.map { WeeklyTotal(weekStart: $0.start, actual: Double($0.totals.gymSets)) },
                           unitLabel: "sets", seriesName: "Sets", color: KXColor.lift,
                           valueFormatter: { "\(Int($0)) sets" }, scale: { $0 })
            WeeklyBarChart(title: "Sessions a week", weeks: weeks.map { WeeklyTotal(weekStart: $0.start, actual: Double($0.totals.sessions)) },
                           unitLabel: "sessions", seriesName: "Sessions", color: KXColor.accent,
                           valueFormatter: { "\(Int($0)) sessions" }, scale: { $0 })
        }
    }

    // MARK: Running trends

    private func runningTrends(_ activities: [ActivityRecord], calendar: Calendar) -> some View {
        let types: [PaceSeries] = [PaceSeries(type: "easy", name: "Easy", color: KXColor.run),
                                   PaceSeries(type: "long", name: "Long", color: KXColor.accent),
                                   PaceSeries(type: "tempo", name: "Tempo", color: KXColor.warning)]
        let series = types.map { item in
            var filled = item
            filled.points = TrainingStats.paceTrend(activities, runType: item.type, weeks: 16, now: .now, calendar: calendar)
            return filled
        }.filter { $0.points.count >= 2 }
        let cadence = TrainingStats.cadenceTrend(activities, weeks: 16, now: .now, calendar: calendar)
        return VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Running trends", subtitle: "Average pace each week by run type (higher is faster)")
            if series.isEmpty {
                Text("Run a few weeks of easy, long and tempo runs to see your pace trends.")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            } else {
                Chart {
                    ForEach(series) { line in
                        ForEach(line.points) { point in
                            LineMark(x: .value("Week", point.weekStart), y: .value("Pace", point.value))
                                .foregroundStyle(by: .value("Run", line.name))
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Week", point.weekStart), y: .value("Pace", point.value))
                                .foregroundStyle(by: .value("Run", line.name))
                                .symbolSize(18)
                        }
                    }
                }
                .chartForegroundStyleScale(domain: series.map(\.name), range: series.map(\.color))
                .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(KXColor.border)
                        AxisValueLabel { if let seconds = value.as(Double.self) { Text(Units.formatPace(Pace(secondsPerKm: seconds), units: units)) } }
                    }
                }
                .frame(height: 180)
            }
            if cadence.count >= 2 {
                Divider().overlay(KXColor.border)
                KXOverline("Cadence")
                Chart(cadence) { point in
                    LineMark(x: .value("Week", point.weekStart), y: .value("Steps per minute", point.value))
                        .foregroundStyle(KXColor.inkSecondary)
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 120)
                Text("Steps per minute, averaged each week.").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
            }
        }
        .kxCard()
    }

    private struct PaceSeries: Identifiable {
        let type: String
        let name: String
        let color: Color
        var points: [TrainingStats.TrendPoint] = []
        var id: String { type }
    }

    // MARK: Strength trends

    private func strengthTrends(calendar: Calendar) -> some View {
        let library = PlanService.templates
        let since = calendar.date(byAdding: .day, value: -28, to: .now) ?? .now
        var setsByMuscle: [MuscleGroup: Int] = [:]
        for log in workouts where log.isFinished && !log.isSoftDeleted && log.startedAt >= since {
            for set in log.sets where set.isCompleted && !set.isSoftDeleted {
                let muscle = library.exercise(id: set.exerciseId)?.muscleGroup ?? .fullBody
                setsByMuscle[muscle, default: 0] += 1
            }
        }
        let rows = setsByMuscle.sorted { $0.value > $1.value }
        let most = Double(rows.first?.value ?? 1)
        return VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Strength", subtitle: "Sets per muscle group, last 4 weeks")
            if rows.isEmpty {
                Text("Finish a few gym sessions to see where your sets go.")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            }
            ForEach(rows, id: \.key) { muscle, sets in
                HStack(spacing: KXSpacing.sm) {
                    Text(muscle.displayName).font(KXFont.callout).foregroundStyle(KXColor.ink).frame(width: 90, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule().fill(KXColor.lift.opacity(0.85))
                            .frame(width: max(6, proxy.size.width * Double(sets) / most), height: 10)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 16)
                    Text("\(sets)").font(KXFont.captionEmphasis.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
                        .frame(width: 32, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard()
    }
}

/// The last six months of training as a calendar: one square per day, darker for bigger days.
struct HeatmapCard: View {
    let days: [TrainingStats.HeatDay]

    var body: some View {
        let calendar = Calendar.kinetix
        // Columns of weeks (Monday at the top).
        let firstMonday = days.first.map { calendar.startOfISOWeek(for: $0.date) } ?? .now
        let weeks = Dictionary(grouping: days) { calendar.startOfISOWeek(for: $0.date) }
        let starts = weeks.keys.sorted()
        let trained = days.filter { $0.level > 0 }.count
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader("Training calendar", subtitle: "\(trained) days in the last 6 months")
            HStack(alignment: .top, spacing: 3) {
                ForEach(starts, id: \.self) { start in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { offset in
                            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                            let level = weeks[start]?.first { calendar.isDate($0.date, inSameDayAs: date) }?.level
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(color(level))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Training calendar: \(trained) training days in the last six months")
            HStack(spacing: 4) {
                Text("Less").font(KXFont.caption2).foregroundStyle(KXColor.inkTertiary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2).fill(color(level)).frame(width: 10, height: 10)
                }
                Text("More").font(KXFont.caption2).foregroundStyle(KXColor.inkTertiary)
                Spacer()
                Text(firstMonday.formatted(.dateTime.month(.abbreviated))).font(KXFont.caption2).foregroundStyle(KXColor.inkTertiary)
            }
        }
        .kxCard()
    }

    private func color(_ level: Int?) -> Color {
        guard let level else { return .clear }
        switch level {
        case 0: return KXColor.surfaceTint
        case 1: return KXColor.accent.opacity(0.3)
        case 2: return KXColor.accent.opacity(0.55)
        case 3: return KXColor.accent.opacity(0.8)
        default: return KXColor.accent
        }
    }
}

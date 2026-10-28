import SwiftUI
import SwiftData
import Charts
import TrainingEngine

/// Running progress: totals, weekly distance against plan, best efforts and every run.
struct RunningProgressView: View {
    let units: UnitSystem

    @Query(sort: \RunLogModel.startedAt, order: .reverse) private var runs: [RunLogModel]
    @Query(sort: \PlannedSessionModel.date) private var sessions: [PlannedSessionModel]
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @State private var filter: RunFilter = .all
    @State private var bests: [BestEffortRow] = []

    private var format: DisplayFormat { DisplayFormat(units: units) }

    /// Shown in the list (simulated runs included, tagged).
    private var finished: [RunLogModel] { runs.filter { $0.isFinished && !$0.isSoftDeleted } }
    /// Counted in totals, charts and best efforts.
    private var counted: [RunLogModel] { finished.filter(\.countsTowardsHistory) }

    enum RunFilter: String, CaseIterable, Identifiable {
        case all = "All", planned = "Planned", recorded = "Recorded", easy = "Easy", long = "Long", quality = "Tempo & intervals"
        var id: String { rawValue }

        func matches(_ run: RunLogModel) -> Bool {
            switch self {
            case .all: return true
            case .planned: return run.plannedSessionId != nil && run.recordTypeRaw == nil
            case .recorded: return run.recordTypeRaw != nil
            case .easy: return run.runType == .easy || run.runType == .recovery
            case .long: return run.runType == .long
            case .quality: return run.runType?.isQuality == true
            }
        }
    }

    struct BestEffortRow: Identifiable, Equatable {
        let distance: BestEffortDistance
        let seconds: Double
        let runId: UUID
        let date: Date
        var id: Double { distance.meters }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xl) {
            if let profile = profiles.first?.profile {
                YourPacesCard(profile: profile, profileModel: profiles.first, format: format)
            }
            totalsCard
            WeeklyBarChart(title: "Weekly distance", weeks: weeklyDistance, unitLabel: Units.distanceUnitLabel(units),
                           seriesName: "Run", color: KXColor.run, valueFormatter: { format.distance($0) },
                           scale: { Units.distance(meters: $0, in: units) })
            bestEffortsCard
            historyCard
        }
        .task(id: counted.count) { bests = computeBests() }
    }

    // MARK: Totals

    private var totalsCard: some View {
        let entries = counted.map { RunHistoryEntry(date: $0.startedAt, distanceMeters: $0.distanceMeters, durationSeconds: $0.durationSeconds) }
        let totals = TrainingHistory.periodTotals(entries, today: .now, calendar: .kinetix)
        return HStack(spacing: KXSpacing.sm) {
            totalTile("This week", totals.week)
            totalTile("This month", totals.month)
            totalTile("This year", totals.year)
        }
    }

    private func totalTile(_ title: String, _ totals: RunTotals) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            KXOverline(title)
            Text(format.distance(totals.distanceMeters)).font(KXFont.headline.monospacedDigit()).foregroundStyle(KXColor.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("\(totals.count) run\(totals.count == 1 ? "" : "s") · \(Units.formatMinutesSeconds(totals.durationSeconds))")
                .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxCard()
        .accessibilityElement(children: .combine)
    }

    private var weeklyDistance: [WeeklyTotal] {
        let calendar = Calendar.kinetix
        var planned: [Date: Double] = [:]
        for session in sessions where !session.isSoftDeleted && session.kind.discipline == .run && session.status != .skipped {
            planned[calendar.startOfISOWeek(for: session.date), default: 0] += session.estimatedDistanceMeters ?? 0
        }
        return TrainingHistory.weekly(counted.map { (date: $0.startedAt, value: $0.distanceMeters) }, weeks: 12, today: .now,
                                      calendar: calendar, planned: planned.filter { $0.value > 0 })
    }

    // MARK: Best efforts

    private func computeBests() -> [BestEffortRow] {
        var best: [BestEffortDistance: BestEffortRow] = [:]
        // Strava's summary map has no timestamps, so imported runs can't give best efforts.
        for run in counted where run.distanceMeters >= BestEffortDistance.oneKilometre.meters && !run.isImportedFromStrava {
            for (distance, seconds) in RunAnalysis.bestEfforts(route: run.route)
            where best[distance].map({ seconds < $0.seconds }) ?? true {
                best[distance] = BestEffortRow(distance: distance, seconds: seconds, runId: run.id, date: run.startedAt)
            }
        }
        return BestEffortDistance.allCases.compactMap { best[$0] }
    }

    private var bestEffortsCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Best efforts", subtitle: "Your fastest time over each distance, from any run")
            if bests.isEmpty {
                KXEmptyState(symbol: "stopwatch", title: "No best efforts yet",
                             message: "Run at least 1 km with GPS and your fastest times show up here.")
            }
            ForEach(bests) { row in
                NavigationLink {
                    if let run = finished.first(where: { $0.id == row.runId }) { RunDetailView(log: run, units: units) }
                } label: {
                    HStack {
                        Image(systemName: "medal.fill").foregroundStyle(KXColor.warning).accessibilityHidden(true)
                        Text(row.distance.displayName).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(Units.formatMinutesSeconds(row.seconds)).font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
                            Text("\(format.pace(Pace(secondsPerKm: row.seconds / row.distance.meters * 1000))) · \(row.date.formatted(.dateTime.day().month().year()))")
                                .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(KXColor.inkTertiary).accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard()
    }

    // MARK: History

    private var filtered: [RunLogModel] { finished.filter(filter.matches) }

    private var months: [(month: Date, runs: [RunLogModel])] {
        let calendar = Calendar.kinetix
        let grouped = Dictionary(grouping: filtered) { calendar.dateInterval(of: .month, for: $0.startedAt)?.start ?? $0.startedAt }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.startedAt > $1.startedAt }) }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("All runs", subtitle: "\(finished.count) run\(finished.count == 1 ? "" : "s")")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: KXSpacing.xs) {
                    ForEach(RunFilter.allCases) { option in
                        KXSelectableChip(text: option.rawValue, isSelected: filter == option) { filter = option }
                    }
                }
            }
            if filtered.isEmpty {
                KXEmptyState(symbol: "figure.run", title: finished.isEmpty ? "No runs yet" : "No runs match",
                             message: finished.isEmpty ? "Finish a planned run or record one from the Record tab."
                                                       : "Try another filter.")
            }
            ForEach(months, id: \.month) { group in
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    HStack {
                        KXOverline(group.month.formatted(.dateTime.month(.wide).year()))
                        Spacer()
                        let monthDistance = group.runs.filter(\.countsTowardsHistory).reduce(0) { $0 + $1.distanceMeters }
                        Text(format.distance(monthDistance)).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    ForEach(group.runs) { run in
                        NavigationLink {
                            RunDetailView(log: run, units: units)
                        } label: {
                            RunHistoryRow(run: run, units: units)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("progress.run")
                    }
                }
            }
        }
        .kxCard()
    }
}

struct RunHistoryRow: View {
    let run: RunLogModel
    let units: UnitSystem

    var body: some View {
        let format = DisplayFormat(units: units)
        HStack(spacing: KXSpacing.md) {
            VStack(spacing: 0) {
                Text(run.startedAt.formatted(.dateTime.day())).font(KXFont.bodyEmphasis.monospacedDigit())
                Text(run.startedAt.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).foregroundStyle(KXColor.inkSecondary)
            }
            .frame(width: 36)
            .foregroundStyle(KXColor.ink)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: KXSpacing.xs) {
                    Text(run.title.isEmpty ? "Run" : run.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink).lineLimit(1)
                    if let tag = run.sourceTag { KXChip(text: tag, variant: .outlined).scaleEffect(0.85) }
                    if run.usedSimulatedGPS { KXChip(text: "Simulated", variant: .outlined).scaleEffect(0.85) }
                }
                Text([run.averagePace.map { format.pace($0) }, run.averageHeartRate.map { "\(Int($0)) bpm" }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            Spacer(minLength: 0)
            Text(format.distance(run.distanceMeters, decimals: 2)).font(KXFont.callout.monospacedDigit()).foregroundStyle(KXColor.ink)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(KXColor.inkTertiary).accessibilityHidden(true)
        }
        .padding(.vertical, KXSpacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Bars per week (last 12), with the planned amount alongside when a plan covered it.
/// Touch a bar to see its values.
struct WeeklyBarChart: View {
    let title: String
    let weeks: [WeeklyTotal]
    let unitLabel: String
    let seriesName: String
    let color: Color
    /// Formats a raw value (metres, kg…) for display.
    let valueFormatter: (Double) -> String
    /// Converts a raw value to the plotted unit (km/mi, tonnes…).
    let scale: (Double) -> Double
    @State private var selectedDate: Date?

    private var hasPlan: Bool { weeks.contains { $0.planned != nil } }

    private var selectedWeek: WeeklyTotal? {
        guard let selectedDate else { return nil }
        let start = Calendar.kinetix.startOfISOWeek(for: selectedDate)
        return weeks.first { $0.weekStart == start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(alignment: .top) {
                KXSectionHeader(title, subtitle: "Last 12 weeks, \(unitLabel)")
                Spacer()
                if let week = selectedWeek ?? weeks.last {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(valueFormatter(week.actual)).font(KXFont.bodyEmphasis.monospacedDigit())
                        Text(week.planned.map { "of \(valueFormatter($0)) planned" }
                             ?? "w/c \(week.weekStart.formatted(.dateTime.day().month()))")
                            .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                }
            }
            Chart {
                ForEach(weeks) { week in
                    if let planned = week.planned {
                        BarMark(x: .value("Week", week.weekStart, unit: .weekOfYear), y: .value(unitLabel, scale(planned)))
                            .foregroundStyle(by: .value("Series", "Planned"))
                            .position(by: .value("Series", "Planned"))
                            .cornerRadius(4)
                    }
                    BarMark(x: .value("Week", week.weekStart, unit: .weekOfYear), y: .value(unitLabel, scale(week.actual)))
                        .foregroundStyle(by: .value("Series", seriesName))
                        .position(by: .value("Series", seriesName))
                        .cornerRadius(4)
                        .opacity(selectedWeek == nil || selectedWeek == week ? 1 : 0.45)
                }
            }
            .chartForegroundStyleScale(domain: hasPlan ? [seriesName, "Planned"] : [seriesName],
                                       range: hasPlan ? [color, KXColor.other] : [color])
            .chartLegend(hasPlan ? .visible : .hidden)
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                    AxisGridLine().foregroundStyle(KXColor.border)
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(KXColor.border)
                    AxisValueLabel()
                }
            }
            .frame(height: 190)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) for the last 12 weeks")
            .accessibilityValue(weeks.suffix(4).map { "Week of \($0.weekStart.formatted(.dateTime.day().month())): \(valueFormatter($0.actual))" }
                                    .joined(separator: ", "))
        }
        .kxCard()
    }
}

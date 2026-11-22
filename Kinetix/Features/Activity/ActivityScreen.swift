import SwiftUI
import SwiftData
import TrainingEngine

/// The Activity tab: Feed (every session, newest first), Stats (overview, running, strength and
/// health) and Achievements (friends, level, points, challenges and badges).
struct ActivityScreen: View {
    enum Section: String, CaseIterable, Identifiable {
        case feed = "Feed", statistics = "Stats", achievements = "Achievements"
        var id: String { rawValue }
        var identifier: String { "activity.section.\(String(describing: self))" }
    }

    static let sectionKey = "activity.section"

    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Query private var runs: [RunLogModel]
    @Query(filter: #Predicate<StrengthLogModel> { $0.isFinished }) private var workouts: [StrengthLogModel]
    @Query(filter: #Predicate<PlannedSessionModel> { $0.deletedAt == nil }) private var sessions: [PlannedSessionModel]
    @State private var integrations = IntegrationSettings.shared
    @AppStorage(ActivityScreen.sectionKey) private var sectionRaw = Section.statistics.rawValue

    private var units: UnitSystem { profiles.first?.units ?? UnitPreference.stored }
    private var section: Section { Section(rawValue: sectionRaw) ?? .statistics }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    KXScreenHeader(title: "Activity")
                    TabTourCard(.activity)
                    HStack(spacing: KXSpacing.xs) {
                        ForEach(Section.allCases) { option in
                            KXSelectableChip(text: option.rawValue, isSelected: section == option) { sectionRaw = option.rawValue }
                                .accessibilityIdentifier(option.identifier)
                        }
                    }
                    switch section {
                    case .feed: ActivityFeedView(units: units, runs: runs, workouts: workouts, external: integrations.loadWorkouts)
                    case .statistics: StatisticsView(units: units, runs: runs, workouts: workouts, external: integrations.loadWorkouts)
                    case .achievements:
                        LevelStrip(runs: runs, workouts: workouts, sessions: sessions, external: integrations.loadWorkouts) {}
                        AchievementsView(units: units)
                    }
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
        }
    }
}

/// "Level 7 · 1,240 XP" with progress to the next level and this week's points. Tap for Achievements.
struct LevelStrip: View {
    let runs: [RunLogModel]
    let workouts: [StrengthLogModel]
    let sessions: [PlannedSessionModel]
    let external: [ExternalWorkout]
    let open: () -> Void

    var body: some View {
        let activities = ActivityRecords.make(runs: runs, lifts: workouts, external: external)
        let planned = ActivityRecords.planned(sessions.filter { $0.plan?.isActive ?? true })
        let weeks = Points.weeks(activities, planned: planned, now: .now, calendar: .kinetix)
        let level = Level(xp: weeks.reduce(0) { $0 + $1.total })
        let thisWeek = weeks.last { Calendar.kinetix.isDate($0.start, equalTo: .now, toGranularity: .weekOfYear) }?.total ?? 0
        Button(action: open) {
            HStack(spacing: KXSpacing.md) {
                LevelBadge(level: level.number, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Level \(level.number)").font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                        Spacer()
                        Text("\(thisWeek) pts this week").font(KXFont.captionEmphasis).foregroundStyle(KXColor.accent)
                    }
                    ProgressView(value: level.progress).tint(KXColor.accent)
                    Text(level.forNext.map { "\(level.intoLevel) of \($0) XP to level \(level.number + 1)" } ?? "Top level")
                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
            }
            .kxCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activity.level")
    }
}

struct LevelBadge: View {
    let level: Int
    var size: CGFloat = 44

    var body: some View {
        Text("\(level)")
            .font(KXFont.number(size * 0.45, relativeTo: .title3))
            .foregroundStyle(KXColor.onAccent)
            .frame(width: size, height: size)
            .background(KXColor.accent, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityLabel("Level \(level)")
    }
}

// MARK: - Activity feed

/// Every session, newest first, grouped by day: runs and gym sessions open their details; runs
/// from other apps show what Apple Health has.
struct ActivityFeedView: View {
    let units: UnitSystem
    let runs: [RunLogModel]
    let workouts: [StrengthLogModel]
    let external: [ExternalWorkout]
    @State private var shown = 40

    private enum Item: Identifiable {
        case run(RunLogModel), gym(StrengthLogModel), other(ExternalWorkout)
        var id: UUID {
            switch self {
            case .run(let run): return run.id
            case .gym(let log): return log.id
            case .other(let workout): return workout.id
            }
        }
        var date: Date {
            switch self {
            case .run(let run): return run.startedAt
            case .gym(let log): return log.startedAt
            case .other(let workout): return workout.start
            }
        }
    }

    private var items: [Item] {
        let finishedRuns = runs.filter { $0.isFinished && !$0.isSoftDeleted }
        let gym = workouts.filter { $0.isFinished && !$0.isSoftDeleted }
        let recorded = finishedRuns.map { DateInterval(start: $0.startedAt, duration: max($0.durationSeconds, 60)) }
            + gym.map { DateInterval(start: $0.startedAt, duration: max($0.durationSeconds, 60)) }
        let others = ExternalWorkouts.notRecorded(external, excluding: recorded)
        return (finishedRuns.map(Item.run) + gym.map(Item.gym) + others.map(Item.other)).sorted { $0.date > $1.date }
    }

    var body: some View {
        let all = items
        let visible = Array(all.prefix(shown))
        let days = Dictionary(grouping: visible) { Calendar.kinetix.startOfDay(for: $0.date) }
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            if all.isEmpty {
                KXEmptyState(symbol: "figure.run", title: "No sessions yet",
                             message: "Runs, gym sessions and workouts from other apps appear here as you do them.")
            }
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXOverline(dayTitle(day))
                    ForEach(days[day] ?? []) { item in row(item) }
                }
            }
            if all.count > shown {
                Button("Show more") { shown += 40 }
                    .buttonStyle(.kx(.outlined, fullWidth: true))
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.kinetix
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    @ViewBuilder
    private func row(_ item: Item) -> some View {
        switch item {
        case .run(let run):
            NavigationLink { RunDetailView(log: run, units: units) } label: { RunHistoryRow(run: run, units: units) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("activity.run")
        case .gym(let log):
            NavigationLink { StrengthSessionDetailView(log: log, units: units) } label: { gymRow(log) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("activity.gym")
        case .other(let workout):
            feedRow(symbol: workout.kind == .run ? "figure.run" : "heart.text.square", tint: workout.kind == .run ? KXColor.run : KXColor.inkSecondary,
                    title: workout.name, detail: otherDetail(workout), tag: "Apple Health")
        }
    }

    private func gymRow(_ log: StrengthLogModel) -> some View {
        let sets = log.sets.filter { $0.isCompleted && !$0.isSoftDeleted }.count
        let minutes = Int((log.durationSeconds / 60).rounded())
        let detail = log.isFunctional
            ? "\(minutes) min" + (log.functionalRunMeters > 0 ? " · \(DisplayFormat(units: units).distance(log.functionalRunMeters)) running" : "")
            : "\(sets) sets · \(minutes) min"
        return feedRow(symbol: log.isFunctional ? "figure.strengthtraining.functional" : "dumbbell.fill", tint: KXColor.lift,
                       title: log.title.isEmpty ? (log.isFunctional ? "Workout" : "Gym session") : log.title, detail: detail,
                       tag: log.isManual ? "Logged by hand" : nil)
    }

    private func otherDetail(_ workout: ExternalWorkout) -> String {
        var parts: [String] = []
        if let meters = workout.distanceMeters, meters > 0 { parts.append(DisplayFormat(units: units).distance(meters)) }
        parts.append(Units.formatMinutesSeconds(workout.durationSeconds))
        if let hr = workout.averageHeartRate { parts.append("\(Int(hr)) bpm") }
        return parts.joined(separator: " · ")
    }

    private func feedRow(symbol: String, tint: Color, title: String, detail: String, tag: String?) -> some View {
        HStack(spacing: KXSpacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink).lineLimit(1)
                Text(detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            Spacer()
            if let tag { KXChip(text: tag, variant: .outlined) }
        }
        .kxCard(padding: KXSpacing.md)
        .accessibilityElement(children: .combine)
    }
}

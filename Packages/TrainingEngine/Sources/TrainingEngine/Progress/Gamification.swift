import Foundation

// MARK: - Sessions, as achievements and statistics see them

/// One finished session (run, gym, functional, or a run from another app).
public struct ActivityRecord: Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case run, gym, functional, other }

    public var id: UUID
    public var start: Date
    public var durationSeconds: Double
    public var kind: Kind
    /// Training load (effort × minutes), as everywhere else in Kinetix.
    public var load: Double
    public var distanceMeters: Double
    /// Run type ("easy", "tempo"…) when known.
    public var runType: String?
    /// Each km's time, for negative splits.
    public var splitSeconds: [Double]
    /// Average cadence (steps per minute), when counted.
    public var cadence: Double?
    /// Gym sets done.
    public var sets: Int

    public init(id: UUID = UUID(), start: Date, durationSeconds: Double, kind: Kind, load: Double, distanceMeters: Double = 0,
                runType: String? = nil, splitSeconds: [Double] = [], cadence: Double? = nil, sets: Int = 0) {
        self.id = id
        self.start = start
        self.durationSeconds = durationSeconds
        self.kind = kind
        self.load = load
        self.distanceMeters = distanceMeters
        self.runType = runType
        self.splitSeconds = splitSeconds
        self.cadence = cadence
        self.sets = sets
    }

    /// Seconds per km (runs over 500 m).
    public var pace: Double? { kind == .run && distanceMeters >= 500 && durationSeconds > 0 ? durationSeconds / (distanceMeters / 1000) : nil }
}

/// A planned session and whether it was done.
public struct PlannedRecord: Equatable, Sendable {
    public var date: Date
    public var completed: Bool

    public init(date: Date, completed: Bool) {
        self.date = date
        self.completed = completed
    }
}

// MARK: - Points

/// Kinetix points: training load plus (weighted more) following the plan.
/// - 1 point per 10 load, at most 60 a day (so overtraining doesn't win);
/// - 20 for each planned session done;
/// - 50 for a week with every planned session done (once the week is over, or all done);
/// - 5 per week in a row with training, at most 50.
public enum Points {
    public static let loadPerPoint = 10.0
    public static let dailyLoadCap = 60
    public static let plannedSession = 20
    public static let fullPlannedWeek = 50
    public static let streakPerWeek = 5
    public static let streakCap = 50

    public struct Week: Equatable, Sendable {
        public var start: Date
        public var load: Int
        public var planned: Int
        public var fullWeek: Int
        public var streak: Int
        public var total: Int { load + planned + fullWeek + streak }
    }

    /// Each week with anything in it, oldest first (the current week included).
    public static func weeks(_ activities: [ActivityRecord], planned: [PlannedRecord], now: Date, calendar: Calendar) -> [Week] {
        let weekOf: (Date) -> Date = { calendar.startOfISOWeek(for: $0) }
        let past = activities.filter { $0.start <= now }
        var loadByDay: [Date: Double] = [:]
        for activity in past { loadByDay[calendar.startOfDay(for: activity.start), default: 0] += activity.load }
        let starts = Set(past.map { weekOf($0.start) } + planned.filter { $0.date <= now }.map { weekOf($0.date) }).sorted()
        let thisWeek = weekOf(now)
        var result: [Week] = []
        var streak = 0
        var previous: Date?
        for start in starts {
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            let load = loadByDay.filter { $0.key >= start && $0.key < end }
                .reduce(0) { $0 + min(dailyLoadCap, Int(($1.value / loadPerPoint).rounded())) }
            let plannedThisWeek = planned.filter { $0.date >= start && $0.date < end }
            let done = plannedThisWeek.filter(\.completed).count
            let allDone = !plannedThisWeek.isEmpty && done == plannedThisWeek.count && (start < thisWeek || plannedThisWeek.count == done)
            let trained = past.contains { $0.start >= start && $0.start < end }
            if trained {
                if let previous, calendar.date(byAdding: .day, value: 7, to: previous).map({ calendar.isDate($0, inSameDayAs: start) }) == true {
                    streak += 1
                } else {
                    streak = 1
                }
                previous = start
            }
            result.append(Week(start: start, load: load, planned: done * plannedSession, fullWeek: allDone ? fullPlannedWeek : 0,
                               streak: trained ? min(streak * streakPerWeek, streakCap) : 0))
        }
        return result
    }

    public static func total(_ activities: [ActivityRecord], planned: [PlannedRecord], now: Date, calendar: Calendar) -> Int {
        weeks(activities, planned: planned, now: now, calendar: calendar).reduce(0) { $0 + $1.total }
    }
}

// MARK: - Levels

/// Levels from all-time points (XP): level 2 at 100 XP, each level about 7% further than the
/// last, up to 50.
public struct Level: Equatable, Sendable {
    public static let maximum = 50
    public var number: Int
    public var xp: Int
    /// XP gained since this level started, and needed for the next.
    public var intoLevel: Int
    public var forNext: Int?

    public var progress: Double {
        guard let forNext, forNext > 0 else { return 1 }
        return min(Double(intoLevel) / Double(forNext), 1)
    }

    static func step(_ level: Int) -> Int { Int((100 * pow(1.07, Double(level - 1))).rounded()) }

    public init(xp: Int) {
        var level = 1
        var floor = 0
        while level < Self.maximum, xp >= floor + Self.step(level) {
            floor += Self.step(level)
            level += 1
        }
        number = level
        self.xp = xp
        intoLevel = xp - floor
        forNext = level < Self.maximum ? Self.step(level) : nil
    }
}

// MARK: - Badge tiers

public enum BadgeTier: String, CaseIterable, Sendable {
    case bronze, silver, gold, platinum
    public var displayName: String { rawValue.capitalized }
}

extension Achievement {
    /// Bronze for the first levels, then silver, gold and platinum for the top one.
    public var tier: BadgeTier? {
        guard level > 0 else { return nil }
        if level >= levelCount { return .platinum }
        let share = Double(level) / Double(levelCount)
        return share <= 0.34 ? .bronze : share <= 0.67 ? .silver : .gold
    }
}

// MARK: - Fun and hidden badges

public struct FunBadge: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    public var symbol: String
    /// Shown as "?" until earned.
    public var isHidden: Bool
    public var value: Double
    public var target: Double
    public var earned: Bool { value >= target }
    public var progress: Double { min(value / max(target, 1), 1) }
}

public enum FunBadges {
    public static func make(_ activities: [ActivityRecord], recordDates: [Date], calendar: Calendar) -> [FunBadge] {
        let sorted = activities.sorted { $0.start < $1.start }
        let hour: (Date) -> Int = { calendar.component(.hour, from: $0) }
        let runs = sorted.filter { $0.kind == .run }
        let days = Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.start) }
        let hybridDays = days.values.filter { day in day.contains { $0.kind == .run } && day.contains { $0.kind == .gym || $0.kind == .functional } }.count
        let negativeSplits = runs.filter { run in
            guard run.distanceMeters >= 5000, run.splitSeconds.count >= 4 else { return false }
            let half = run.splitSeconds.count / 2
            return run.splitSeconds.suffix(half).reduce(0, +) < run.splitSeconds.prefix(half).reduce(0, +)
        }.count
        let longest = runs.map(\.distanceMeters).max() ?? 0
        let weeks = Dictionary(grouping: sorted) { calendar.startOfISOWeek(for: $0.start) }
        let biggestWeek = weeks.values.map(\.count).max() ?? 0
        let weekendsBoth = weeks.values.filter { week in
            let weekdays = Set(week.map { calendar.component(.weekday, from: $0.start) })
            return weekdays.contains(7) && weekdays.contains(1)
        }.count
        let recordWeeks = Dictionary(grouping: recordDates) { calendar.startOfISOWeek(for: $0) }.values.map(\.count).max() ?? 0
        let newYear = sorted.contains { calendar.component(.month, from: $0.start) == 1 && calendar.component(.day, from: $0.start) == 1 }
        var comeback = false
        for (a, b) in zip(sorted, sorted.dropFirst()) where b.start.timeIntervalSince(a.start) >= 14 * 86_400 { comeback = true }

        return [
            FunBadge(id: "earlyBird", name: "Early bird", detail: "5 sessions started before 7am", symbol: "sunrise.fill",
                     isHidden: false, value: Double(sorted.filter { hour($0.start) < 7 }.count), target: 5),
            FunBadge(id: "nightOwl", name: "Night owl", detail: "5 sessions started after 8pm", symbol: "moon.stars.fill",
                     isHidden: false, value: Double(sorted.filter { hour($0.start) >= 20 }.count), target: 5),
            FunBadge(id: "hybridDay", name: "Hybrid day", detail: "A run and a gym session on the same day", symbol: "figure.run.circle",
                     isHidden: false, value: Double(hybridDays), target: 1),
            FunBadge(id: "hybridHero", name: "Hybrid hero", detail: "10 hybrid days", symbol: "bolt.heart.fill",
                     isHidden: false, value: Double(hybridDays), target: 10),
            FunBadge(id: "negativeSplit", name: "Negative split", detail: "Run the second half of a 5 km+ run faster than the first",
                     symbol: "arrow.down.right", isHidden: false, value: Double(negativeSplits), target: 1),
            FunBadge(id: "doubleDigits", name: "Double digits", detail: "A 10 km run", symbol: "10.circle.fill",
                     isHidden: false, value: longest >= 10_000 ? 1 : 0, target: 1),
            FunBadge(id: "weekendWarrior", name: "Weekend warrior", detail: "Train on Saturday and Sunday, 4 weekends", symbol: "calendar.badge.checkmark",
                     isHidden: false, value: Double(weekendsBoth), target: 4),
            FunBadge(id: "halfway", name: "Halfway there", detail: "A half-marathon distance run", symbol: "flag.checkered",
                     isHidden: true, value: longest >= 21_097 ? 1 : 0, target: 1),
            FunBadge(id: "marathoner", name: "Marathoner", detail: "A marathon distance run", symbol: "medal.fill",
                     isHidden: true, value: longest >= 42_195 ? 1 : 0, target: 1),
            FunBadge(id: "ironWeek", name: "Iron week", detail: "7 sessions in one week", symbol: "flame.circle.fill",
                     isHidden: true, value: Double(biggestWeek), target: 7),
            FunBadge(id: "pbWeek", name: "PB week", detail: "2 personal records in one week", symbol: "trophy.circle.fill",
                     isHidden: true, value: Double(recordWeeks), target: 2),
            FunBadge(id: "newYear", name: "New year, same me", detail: "Train on 1 January", symbol: "sparkles",
                     isHidden: true, value: newYear ? 1 : 0, target: 1),
            FunBadge(id: "comeback", name: "Comeback", detail: "Train again after two weeks off", symbol: "arrow.uturn.up.circle.fill",
                     isHidden: true, value: comeback ? 1 : 0, target: 1),
        ]
    }
}

// MARK: - Monthly challenges

public struct Challenge: Identifiable, Codable, Equatable, Sendable {
    public enum Metric: String, Codable, Sendable { case runKilometres, gymSessions, activeDays, plannedShare }

    /// e.g. "2026-12-runKilometres" (the same for everyone, so friends can compare).
    public var id: String
    public var title: String
    public var detail: String
    public var symbol: String
    public var metric: Metric
    public var target: Double
    public var start: Date
    public var end: Date

    public init(id: String, title: String, detail: String, symbol: String, metric: Metric, target: Double, start: Date, end: Date) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.metric = metric
        self.target = target
        self.start = start
        self.end = end
    }
}

public enum MonthlyChallenges {
    /// The month's four challenges (the same for everyone).
    public static func forMonth(containing date: Date, calendar: Calendar) -> [Challenge] {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        let month = start.formatted(.dateTime.month(.wide))
        let key = String(format: "%04d-%02d", calendar.component(.year, from: start), calendar.component(.month, from: start))
        // A little harder every other month, so it doesn't feel the same.
        let even = calendar.component(.month, from: start) % 2 == 0
        let km: Double = even ? 100 : 75
        let gym: Double = even ? 12 : 10
        return [
            Challenge(id: "\(key)-runKilometres", title: "\(Int(km)) km in \(month)", detail: "Run \(Int(km)) km this month",
                      symbol: "road.lanes", metric: .runKilometres, target: km, start: start, end: end),
            Challenge(id: "\(key)-gymSessions", title: "\(Int(gym)) gym sessions", detail: "\(Int(gym)) gym or functional sessions in \(month)",
                      symbol: "dumbbell.fill", metric: .gymSessions, target: gym, start: start, end: end),
            Challenge(id: "\(key)-activeDays", title: "16 active days", detail: "Train on 16 different days in \(month)",
                      symbol: "calendar", metric: .activeDays, target: 16, start: start, end: end),
            Challenge(id: "\(key)-plannedShare", title: "Plan perfect", detail: "Do 90% of your planned sessions in \(month)",
                      symbol: "checkmark.seal.fill", metric: .plannedShare, target: 90, start: start, end: end),
        ]
    }

    /// Progress towards a challenge (km, sessions, days or % of planned sessions done).
    public static func value(_ challenge: Challenge, activities: [ActivityRecord], planned: [PlannedRecord], calendar: Calendar) -> Double {
        let inside = activities.filter { $0.start >= challenge.start && $0.start < challenge.end }
        switch challenge.metric {
        case .runKilometres: return (inside.filter { $0.kind == .run }.reduce(0) { $0 + $1.distanceMeters } / 1000 * 10).rounded(.down) / 10
        case .gymSessions: return Double(inside.filter { $0.kind == .gym || $0.kind == .functional }.count)
        case .activeDays: return Double(Set(inside.map { calendar.startOfDay(for: $0.start) }).count)
        case .plannedShare:
            let due = planned.filter { $0.date >= challenge.start && $0.date < challenge.end }
            guard !due.isEmpty else { return 0 }
            return (Double(due.filter(\.completed).count) / Double(due.count) * 100).rounded()
        }
    }
}

// MARK: - Statistics

public enum TrainingStats {
    public struct Totals: Equatable, Sendable {
        public var sessions = 0
        public var runs = 0
        public var gymSessions = 0
        public var runMeters = 0.0
        public var seconds = 0.0
        public var gymSets = 0
    }

    public static func totals(_ activities: [ActivityRecord], from: Date, to: Date) -> Totals {
        var totals = Totals()
        for activity in activities where activity.start >= from && activity.start < to {
            totals.sessions += 1
            totals.seconds += activity.durationSeconds
            switch activity.kind {
            case .run:
                totals.runs += 1
                totals.runMeters += activity.distanceMeters
            case .gym, .functional:
                totals.gymSessions += 1
                totals.gymSets += activity.sets
                totals.runMeters += activity.distanceMeters
            case .other:
                break
            }
        }
        return totals
    }

    public struct WeekVolume: Equatable, Sendable, Identifiable {
        public var start: Date
        public var totals: Totals
        public var id: Date { start }
    }

    /// The last `weeks` weeks (this one included), oldest first.
    public static func weekly(_ activities: [ActivityRecord], weeks: Int, now: Date, calendar: Calendar) -> [WeekVolume] {
        let thisWeek = calendar.startOfISOWeek(for: now)
        return (0..<weeks).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .day, value: -7 * back, to: thisWeek),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
            return WeekVolume(start: start, totals: totals(activities, from: start, to: end))
        }
    }

    /// Average runs a week over the last full `weeks` weeks.
    public static func averageRunsPerWeek(_ activities: [ActivityRecord], weeks: Int = 12, now: Date, calendar: Calendar) -> Double {
        let thisWeek = calendar.startOfISOWeek(for: now)
        guard let from = calendar.date(byAdding: .day, value: -7 * weeks, to: thisWeek) else { return 0 }
        let runs = activities.filter { $0.kind == .run && $0.start >= from && $0.start < thisWeek }.count
        return (Double(runs) / Double(weeks) * 10).rounded() / 10
    }

    public struct HeatDay: Equatable, Sendable, Identifiable {
        public var date: Date
        /// 0 = rest, 1–4 = light to big day (by load).
        public var level: Int
        public var id: Date { date }
    }

    /// The last `days` days for a calendar heatmap, oldest first.
    public static func heatmap(_ activities: [ActivityRecord], days: Int, now: Date, calendar: Calendar) -> [HeatDay] {
        var load: [Date: Double] = [:]
        for activity in activities { load[calendar.startOfDay(for: activity.start), default: 0] += max(activity.load, 1) }
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let value = load[day] ?? 0
            let level = value <= 0 ? 0 : value < 150 ? 1 : value < 300 ? 2 : value < 500 ? 3 : 4
            return HeatDay(date: day, level: level)
        }
    }

    public struct TrendPoint: Equatable, Sendable, Identifiable {
        public var weekStart: Date
        public var value: Double
        public var id: Date { weekStart }
    }

    /// Weekly average pace (s/km) for one run type over the last `weeks` weeks (weeks without it left out).
    public static func paceTrend(_ activities: [ActivityRecord], runType: String, weeks: Int, now: Date, calendar: Calendar) -> [TrendPoint] {
        trend(activities.filter { $0.kind == .run && $0.runType == runType && $0.pace != nil }, weeks: weeks, now: now, calendar: calendar) { runs in
            let meters = runs.reduce(0) { $0 + $1.distanceMeters }
            return meters > 0 ? runs.reduce(0) { $0 + $1.durationSeconds } / (meters / 1000) : nil
        }
    }

    /// Weekly average cadence over the last `weeks` weeks.
    public static func cadenceTrend(_ activities: [ActivityRecord], weeks: Int, now: Date, calendar: Calendar) -> [TrendPoint] {
        trend(activities.filter { $0.kind == .run && $0.cadence != nil }, weeks: weeks, now: now, calendar: calendar) { runs in
            let values = runs.compactMap(\.cadence)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
    }

    private static func trend(_ activities: [ActivityRecord], weeks: Int, now: Date, calendar: Calendar,
                              value: ([ActivityRecord]) -> Double?) -> [TrendPoint] {
        let thisWeek = calendar.startOfISOWeek(for: now)
        return (0..<weeks).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .day, value: -7 * back, to: thisWeek),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
            let inWeek = activities.filter { $0.start >= start && $0.start < end }
            return value(inWeek).map { TrendPoint(weekStart: start, value: $0) }
        }
    }
}

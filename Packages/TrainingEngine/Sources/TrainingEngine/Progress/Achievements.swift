import Foundation

/// Badges for showing up: check-ins, runs, distance, gym sessions, functional workouts,
/// personal records and weeks in a row of training. Each kind has rising levels.
public struct AchievementStats: Equatable, Sendable {
    public var checkIns: Int
    public var runs: Int
    public var runMeters: Double
    public var gymSessions: Int
    public var functionalWorkouts: Int
    public var personalRecords: Int
    /// Start of each day something was done (runs, gym, functional), for the streak.
    public var trainingDays: [Date]

    public init(checkIns: Int = 0, runs: Int = 0, runMeters: Double = 0, gymSessions: Int = 0, functionalWorkouts: Int = 0,
                personalRecords: Int = 0, trainingDays: [Date] = []) {
        self.checkIns = checkIns
        self.runs = runs
        self.runMeters = runMeters
        self.gymSessions = gymSessions
        self.functionalWorkouts = functionalWorkouts
        self.personalRecords = personalRecords
        self.trainingDays = trainingDays
    }
}

public struct Achievement: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case checkIns, runs, distance, gym, functional, records, streak

        public var title: String {
            switch self {
            case .checkIns: return "Check-ins"
            case .runs: return "Runs"
            case .distance: return "Distance"
            case .gym: return "Gym sessions"
            case .functional: return "Functional"
            case .records: return "Records"
            case .streak: return "Weeks in a row"
            }
        }

        public var symbol: String {
            switch self {
            case .checkIns: return "checkmark.seal.fill"
            case .runs: return "figure.run"
            case .distance: return "road.lanes"
            case .gym: return "dumbbell.fill"
            case .functional: return "figure.strengthtraining.functional"
            case .records: return "trophy.fill"
            case .streak: return "flame.fill"
            }
        }

        /// Each level's target.
        public var levels: [Double] {
            switch self {
            case .checkIns: return [1, 7, 25, 50, 100, 250, 365]
            case .runs: return [1, 10, 25, 50, 100, 250, 500]
            case .distance: return [10, 50, 100, 250, 500, 1000, 2500]   // km
            case .gym: return [1, 10, 25, 50, 100, 250]
            case .functional: return [1, 5, 10, 25, 50]
            case .records: return [1, 5, 10, 25, 50, 100]
            case .streak: return [2, 4, 8, 12, 26, 52]                    // weeks
            }
        }

        func name(_ target: Double) -> String {
            let n = Int(target)
            switch self {
            case .checkIns: return n == 1 ? "First check-in" : "\(n) check-ins"
            case .runs: return n == 1 ? "First run" : "\(n) runs"
            case .distance: return "\(n) km run"
            case .gym: return n == 1 ? "First gym session" : "\(n) gym sessions"
            case .functional: return n == 1 ? "First functional workout" : "\(n) functional workouts"
            case .records: return n == 1 ? "First record" : "\(n) records"
            case .streak: return "\(n) weeks in a row"
            }
        }
    }

    public var kind: Kind
    /// Levels reached (0 = none yet).
    public var level: Int
    public var value: Double
    public var id: String { kind.rawValue }

    public var levelCount: Int { kind.levels.count }
    public var isMaxed: Bool { level >= levelCount }
    /// The latest badge earned, e.g. "50 check-ins".
    public var earnedName: String? { level > 0 ? kind.name(kind.levels[level - 1]) : nil }
    /// The next badge, e.g. "100 check-ins".
    public var nextName: String? { isMaxed ? nil : kind.name(kind.levels[level]) }
    public var nextTarget: Double? { isMaxed ? nil : kind.levels[level] }
    /// 0–1 towards the next level.
    public var progress: Double {
        guard let next = nextTarget else { return 1 }
        let previous = level > 0 ? kind.levels[level - 1] : 0
        return min(max((value - previous) / max(next - previous, 1), 0), 1)
    }
}

public enum Achievements {
    public static func make(_ stats: AchievementStats, now: Date = .now, calendar: Calendar = .kinetix) -> [Achievement] {
        Achievement.Kind.allCases.map { kind in
            let value: Double
            switch kind {
            case .checkIns: value = Double(stats.checkIns)
            case .runs: value = Double(stats.runs)
            case .distance: value = (stats.runMeters / 1000).rounded(.down)
            case .gym: value = Double(stats.gymSessions)
            case .functional: value = Double(stats.functionalWorkouts)
            case .records: value = Double(stats.personalRecords)
            case .streak: value = Double(longestWeekStreak(stats.trainingDays, calendar: calendar))
            }
            let level = kind.levels.filter { value >= $0 }.count
            return Achievement(kind: kind, level: level, value: value)
        }
    }

    /// The most weeks in a row (Monday–Sunday) with at least one session.
    public static func longestWeekStreak(_ days: [Date], calendar: Calendar = .kinetix) -> Int {
        let weeks = Set(days.map { calendar.startOfISOWeek(for: $0) }).sorted()
        var best = 0, run = 0
        var previous: Date?
        for week in weeks {
            if let previous, let next = calendar.date(byAdding: .day, value: 7, to: previous),
               calendar.isDate(next, inSameDayAs: week) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = week
        }
        return best
    }

    /// Badges earned now that weren't before (to celebrate them once).
    public static func newlyEarned(before: [Achievement], after: [Achievement]) -> [String] {
        after.compactMap { now in
            let old = before.first { $0.kind == now.kind }?.level ?? 0
            return now.level > old ? now.earnedName : nil
        }
    }
}

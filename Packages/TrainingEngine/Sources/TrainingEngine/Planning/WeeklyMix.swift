import Foundation

/// How many runs and lifts a week holds, and of which types.
public struct WeeklyMix: Equatable, Sendable {
    public var trainingDays: [Weekday]
    public var doubleDays: Int
    public var runs: [RunSessionType]
    public var lifts: [StrengthSessionTemplate]
    public var notes: [String]
}

enum MixBuilder {
    /// Training days with a guaranteed rest day (7 days → Friday off).
    static func effectiveDays(_ days: [Weekday]) -> (days: [Weekday], note: String?) {
        let unique = Array(Set(days)).sorted()
        if unique.count >= 7 {
            return (unique.filter { $0 != .friday }, "Friday is a rest day: at least one full rest day a week helps you absorb training.")
        }
        return (unique, nil)
    }

    static func sessionCounts(profile: AthleteProfile, rules: PlanRules) -> (runs: Int, lifts: Int, days: [Weekday], doubles: Int, notes: [String]) {
        var notes: [String] = []
        let (days, note) = effectiveDays(profile.trainingDays)
        if let note { notes.append(note) }
        let doubles = min(max(profile.doubleSessionDays, 0), days.count)
        let slots = days.count + doubles
        let goal = rules.goal(profile.goal)

        var lifts = Int((Double(slots) * (1 - goal.runShare)).rounded())
        lifts = min(max(lifts, goal.minLifts), goal.maxLifts, days.count, max(slots - 1, 0))
        var runs = min(slots - lifts, days.count)
        // If runs were capped by days, give the spare slot back to lifting where allowed.
        lifts = min(slots - runs, goal.maxLifts, days.count)
        if slots == 1 { runs = profile.goal.isRunningFocused ? 1 : 0; lifts = 1 - runs }
        return (max(runs, 0), max(lifts, 0), days, doubles, notes)
    }

    static func build(
        profile: AthleteProfile,
        week: WeekTarget,
        templates: TemplateLibrary
    ) -> WeeklyMix {
        let rules = templates.rules
        let goal = rules.goal(profile.goal)
        let counts = sessionCounts(profile: profile, rules: rules)

        var quality = min(rules.qualityCount(level: profile.runningExperience, phase: week.phase), goal.maxQuality)
        if week.isRecoveryWeek { quality = min(quality, 1) }

        var runs: [RunSessionType] = []
        let qualityTypes: (Int) -> [RunSessionType] = { count in
            var order = goal.qualityOrder.isEmpty ? [.tempo, .intervals] : goal.qualityOrder
            // Base phase builds aerobic strength: tempo only, no VO2max intervals.
            if week.phase == .base { order = [.tempo] }
            return (0..<count).map { order[$0 % order.count] }
        }

        switch counts.runs {
        case 0:
            break
        case 1:
            runs = quality > 0 ? qualityTypes(1) : [.easy]
        case 2:
            runs = [.long] + (quality > 0 ? qualityTypes(1) : [.easy])
        default:
            let q = min(quality, counts.runs - 2)
            runs = [.long] + qualityTypes(q) + Array(repeating: .easy, count: counts.runs - 1 - q)
        }

        let lifts = templates.split(liftingDays: counts.lifts)
        return WeeklyMix(trainingDays: counts.days, doubleDays: counts.doubles, runs: runs, lifts: lifts, notes: counts.notes)
    }
}

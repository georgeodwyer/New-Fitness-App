import Foundation

// Programmes written by the coach in the programmes workbook and converted to
// `programmes.json` by scripts/import_programmes.py. Running volume is written as a share
// of the runner's starting volume and paces as zones, so one programme fits everyone:
// the app sizes every run from the runner's onboarding answers.

/// The converted workbook.
public struct ProgrammeFile: Codable, Equatable, Sendable {
    public var version: Int
    /// Safety limits by experience level (`beginner`, `intermediate`, `advanced`).
    public var rules: [String: ProgrammeRules]
    public var programmes: [Programme]

    /// Which running levels see each goal in onboarding (goals not listed: everyone).
    public var availability: [String: [String]]? = nil
    /// Runs and lifts per week and the suggested split, for every goal.
    public var goals: [String: GoalSettings]? = nil
    /// Gym splits and sets/reps by goal, from the workbook.
    public var strength: WorkbookStrength? = nil

    public func settings(for goal: TrainingGoal) -> GoalSettings? { goals?[goal.rawValue] }

    public static let empty = ProgrammeFile(version: 1, rules: [:], programmes: [])

    /// Whether a runner at this level is offered the goal.
    public func isGoal(_ goal: TrainingGoal, availableTo level: ExperienceLevel) -> Bool {
        guard let levels = availability?[goal.rawValue] else { return true }
        return levels.contains(level.rawValue)
    }

    public func programme(for goal: TrainingGoal) -> Programme? {
        programmes.first { $0.goal == goal && !$0.weeks.isEmpty }
    }

    public func rules(for level: ExperienceLevel) -> ProgrammeRules {
        rules[level.rawValue] ?? .fallback
    }
}

/// The Rules tab, for one experience level.
public struct ProgrammeRules: Codable, Equatable, Sendable {
    /// Starting volume when the runner doesn't run yet or doesn't know.
    public var defaultStartMeters: Double
    public var minStartMeters: Double
    public var maxStartMeters: Double
    /// No single run is longer than this.
    public var longestRunMeters: Double
    /// Runs shorter than this are dropped.
    public var shortestRunMeters: Double
    /// A week is never more than this much above the biggest of the last few weeks.
    public var maxWeeklyIncrease: Double
    /// Long run's share of the week when the programme says "auto".
    public var longRunShare: Double
    // Sizing rules (optional in the file; the defaults are the values agreed with the coach).
    /// Warm-up and cool-down, each, as a share of the week, kept between min and max.
    public var warmUpShare: Double? = nil
    public var warmUpMinMeters: Double? = nil
    public var warmUpMaxMeters: Double? = nil
    /// Hard running per session as a share of the week, with a floor: fast (I, R, 5K, hills),
    /// threshold (T, 10K) and steady (STEADY, M, HM).
    public var fastRepsShare: Double? = nil
    public var fastRepsFloorMeters: Double? = nil
    public var thresholdRepsShare: Double? = nil
    public var thresholdRepsFloorMeters: Double? = nil
    public var steadyRepsShare: Double? = nil
    public var steadyRepsFloorMeters: Double? = nil
    /// Longest recovery and easy runs as a share of the long run; shakeout as a share of the week.
    public var recoveryRunOfLong: Double? = nil
    public var easyRunOfLong: Double? = nil
    public var shakeoutOfWeek: Double? = nil
    /// The easy week after the programme, as a share of the starting volume.
    public var recoveryWeekShare: Double? = nil
    /// How fast volume comes down to race-ready when the runner is doing more (per week).
    public var easeDownPerWeek: Double? = nil
    /// The easy first week after a race, as a share of current volume.
    public var easyStartShare: Double? = nil

    var warmUp: Double { warmUpShare ?? 0.06 }
    var warmUpMin: Double { warmUpMinMeters ?? 1500 }
    var warmUpMax: Double { warmUpMaxMeters ?? 2500 }
    var recoveryRunLimit: Double { recoveryRunOfLong ?? 0.6 }
    var easyRunLimit: Double { easyRunOfLong ?? 0.85 }
    var shakeoutLimit: Double { shakeoutOfWeek ?? 0.15 }
    var recoveryWeek: Double { recoveryWeekShare ?? 0.6 }
    var easeDown: Double { easeDownPerWeek ?? 0.15 }
    var easyStart: Double { easyStartShare ?? 0.6 }

    public static let fallback = ProgrammeRules(defaultStartMeters: 15000, minStartMeters: 10000, maxStartMeters: 60000,
                                                longestRunMeters: 21000, shortestRunMeters: 3000, maxWeeklyIncrease: 0.1,
                                                longRunShare: 0.3)
}

public struct Programme: Codable, Equatable, Sendable {
    public var goal: TrainingGoal
    public var name: String
    public var description: String
    public var lengthWeeks: Int
    /// `repeat`, `repeatHarder`, `maintenance` or `stop`.
    public var afterLastWeek: String
    public var runsPerWeekMin: Int
    public var runsPerWeekMax: Int
    public var longRunCapMeters: Double
    public var weeklyCapMeters: Double?
    /// The weekly volume this race needs, by level (`beginner`, `intermediate`, `advanced`).
    public var raceReadyMeters: [String: Double]? = nil
    public var taperWeeks: Int
    public var weeks: [ProgrammeWeek]
    public var sessions: [ProgrammeSession]

    public func week(_ number: Int) -> ProgrammeWeek? { weeks.first { $0.week == number } }

    public func raceReady(for level: ExperienceLevel) -> Double? {
        raceReadyMeters?[level.rawValue].flatMap { $0 > 0 ? $0 : nil }
    }

    public func sessions(inWeek number: Int) -> [ProgrammeSession] {
        sessions.filter { $0.week == number }.sorted { $0.order < $1.order }
    }

    /// The race at the end of a running goal.
    public var raceDistanceMeters: Double? {
        switch goal {
        case .first5k: return 5000
        case .faster5k: return 5000
        case .faster10k: return 10000
        case .halfMarathon: return 21097.5
        case .marathon: return 42195
        default: return nil
        }
    }

    /// The pace the race is run at.
    var racePaceZone: PaceZone {
        switch goal {
        case .first5k, .faster5k: return .fiveK
        case .faster10k: return .tenK
        case .halfMarathon: return .halfMarathon
        default: return .marathon
        }
    }
}

public struct ProgrammeWeek: Codable, Equatable, Sendable {
    public var week: Int
    public var phase: TrainingPhase
    public var isDeload: Bool
    public var isRaceWeek: Bool
    /// Running volume as a share of the starting volume (1.0 = starting volume).
    public var volume: Double
    public var longRun: ProgrammeDistance
    /// `normal`, `heavy`, `light` or `none`.
    public var strength: String
    public var note: String?
}

/// auto, a share of the week, a fixed distance, or the race.
public struct ProgrammeDistance: Codable, Equatable, Sendable {
    public var kind: String
    public var value: Double?

    public static let auto = ProgrammeDistance(kind: "auto", value: nil)
}

public struct ProgrammeSession: Codable, Equatable, Sendable {
    public var week: Int
    public var order: Int
    /// Shown in the app, e.g. "Fartlek", "Progression run".
    public var name: String
    /// `easy`, `recovery`, `long`, `tempo`, `intervals` or `race`.
    public var type: String
    public var distance: ProgrammeDistance
    public var parts: [WorkoutPart]
    /// The workout as written in the workbook.
    public var text: String?
    public var note: String?

    var isRace: Bool { type == "race" }

    /// How the scheduler and training load treat the session.
    var runType: RunSessionType {
        switch type {
        case "race", "long": return .long
        default: return RunSessionType(rawValue: type) ?? .easy
        }
    }

    /// Has reps or a set block of hard running (gets a warm-up and cool-down).
    var isStructured: Bool {
        parts.contains { part in
            part.kind == "reps" && (part.steps ?? []).contains { !$0.isRecovery && $0.label != "Stride" }
        }
    }
}

/// One part of a workout: a share of the run at a pace, a block of reps, or the race.
public struct WorkoutPart: Codable, Equatable, Sendable {
    /// `share`, `reps` or `race`.
    public var kind: String
    public var share: Double?
    public var zone: String?
    public var repeats: Int?
    public var steps: [WorkoutStepSpec]?
    /// Recovery between reps (not after the last).
    public var recovery: WorkoutStepSpec?
}

public struct WorkoutStepSpec: Codable, Equatable, Sendable {
    public var meters: Double?
    public var seconds: Double?
    /// A pace zone, or `hill` (run by effort, no pace).
    public var zone: String
    public var effort: Bool?
    public var recovery: Bool?
    public var label: String?

    var isRecovery: Bool { recovery == true }
}

extension TemplateLibrary {
    /// Loads the coach's programmes shipped with the app (empty if there are none).
    static func bundledProgrammes() -> ProgrammeFile {
        guard let url = Bundle.module.url(forResource: "programmes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ProgrammeFile.self, from: data)
        else { return .empty }
        return file
    }
}

/// The Programmes tab's per-goal settings.
public struct GoalSettings: Codable, Equatable, Sendable {
    public var runsMin: Int
    public var runsMax: Int
    public var liftsMin: Int
    public var liftsMax: Int
    /// The split suggested in onboarding (a `WorkbookSplit.code`).
    public var defaultSplit: String?
}

/// The workbook's gym splits and sets/reps by goal.
public struct WorkbookStrength: Codable, Equatable, Sendable {
    public var splits: [WorkbookSplit]
    public var byGoal: [String: GoalPrescription]

    public func split(_ code: String) -> WorkbookSplit? { splits.first { $0.code == code } }

    /// The splits to offer for a number of gym sessions a week: those with that many days,
    /// plus Upper / Lower (its first upper and lower days) for two.
    public func offered(sessions: Int) -> [WorkbookSplit] {
        splits.filter { $0.shown && ($0.days.count == sessions || ($0.code == "upperLower" && sessions == 2)) }
    }
}

public struct WorkbookSplit: Codable, Equatable, Sendable, Identifiable {
    public var code: String
    public var name: String
    public var suits: String
    public var shown: Bool
    public var days: [StrengthSessionTemplate]
    public var id: String { code }
}

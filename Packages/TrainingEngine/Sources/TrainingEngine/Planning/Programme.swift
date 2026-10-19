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

    public static let empty = ProgrammeFile(version: 1, rules: [:], programmes: [])

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
    public var taperWeeks: Int
    public var weeks: [ProgrammeWeek]
    public var sessions: [ProgrammeSession]

    public func week(_ number: Int) -> ProgrammeWeek? { weeks.first { $0.week == number } }

    public func sessions(inWeek number: Int) -> [ProgrammeSession] {
        sessions.filter { $0.week == number }.sorted { $0.order < $1.order }
    }

    /// The race at the end of a running goal.
    public var raceDistanceMeters: Double? {
        switch goal {
        case .first5k: return 5000
        case .faster10k: return 10000
        case .halfMarathon: return 21097.5
        case .marathon: return 42195
        default: return nil
        }
    }

    /// The pace the race is run at.
    var racePaceZone: PaceZone {
        switch goal {
        case .first5k: return .fiveK
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

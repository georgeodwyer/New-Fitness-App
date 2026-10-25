import Foundation

// MARK: - Run workouts

public struct SegmentSpec: Codable, Equatable, Sendable {
    public var durationSeconds: Double?
    public var distanceMeters: Double?
    public var zone: PaceZone
}

public struct WorkoutBlock: Codable, Equatable, Sendable {
    public var repeats: Int
    public var work: SegmentSpec
    public var recovery: SegmentSpec?
}

public struct RunWorkoutTemplate: Codable, Equatable, Sendable {
    public var id: String
    public var type: RunSessionType
    public var level: ExperienceLevel
    public var name: String
    public var warmUpMinutes: Double
    public var coolDownMinutes: Double
    public var blocks: [WorkoutBlock]
}

struct RunWorkoutFile: Codable {
    var workouts: [RunWorkoutTemplate]
}

// MARK: - Exercises

public enum ExerciseLoading: String, Codable, Sendable {
    case barbell, dumbbell, machine, bodyweight
}

public enum BodyRegion: String, Codable, Sendable {
    case upper, lower, core
}

/// Starts an exercise at a share of a main lift's working weight (e.g. dumbbell bench at 40%
/// of the barbell bench weight, per hand).
public struct LiftLink: Codable, Equatable, Sendable {
    public var lift: MainLift
    public var ratio: Double

    public init(lift: MainLift, ratio: Double) {
        self.lift = lift
        self.ratio = ratio
    }
}

public struct ExerciseDefinition: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var pattern: String
    public var requires: Equipment
    public var loading: ExerciseLoading
    public var region: BodyRegion
    public var mainLift: MainLift?
    public var defaultWeightKg: [String: Double]?
    /// Main muscle group, for the gym tracker's filters (worked out from `pattern` when absent).
    public var muscle: MuscleGroup?
    /// Extra exercises for the gym tracker only; never chosen when generating plans.
    public var libraryOnly: Bool?
    /// Takes its starting weight from this main lift's number (variations of the big lifts).
    public var liftLink: LiftLink?

    public init(id: String, name: String, pattern: String, requires: Equipment, loading: ExerciseLoading, region: BodyRegion,
                mainLift: MainLift? = nil, defaultWeightKg: [String: Double]? = nil, muscle: MuscleGroup? = nil, libraryOnly: Bool? = nil,
                liftLink: LiftLink? = nil) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.requires = requires
        self.loading = loading
        self.region = region
        self.mainLift = mainLift
        self.defaultWeightKg = defaultWeightKg
        self.muscle = muscle
        self.libraryOnly = libraryOnly
        self.liftLink = liftLink
    }

    public var muscleGroup: MuscleGroup { muscle ?? MuscleGroup(pattern: pattern) }

    public func defaultWeight(for level: ExperienceLevel) -> Double? {
        defaultWeightKg?[level.rawValue]
    }
}

struct ExerciseFile: Codable {
    var exercises: [ExerciseDefinition]
}

extension Equipment {
    /// Higher rank = more equipment. An exercise is available when its requirement ≤ the user's rank.
    public var rank: Int {
        switch self {
        case .bodyweight: return 0
        case .dumbbellsOnly: return 1
        case .homeGym: return 2
        case .fullGym: return 3
        }
    }

    public func allows(_ requirement: Equipment) -> Bool { requirement.rank <= rank }
}

// MARK: - Strength programmes

public struct ExerciseSlot: Codable, Equatable, Sendable {
    /// A movement pattern (the app picks the exercise for the user's equipment), or "named".
    public var pattern: String
    public var role: SlotRole
    /// A specific exercise written by the coach (swapped for the closest option if the user's
    /// equipment can't do it).
    public var exerciseName: String? = nil
    /// The coach's sets/reps/rest for this exercise (blank = the goal's defaults for the role).
    public var sets: Int? = nil
    public var repsLow: Int? = nil
    public var repsHigh: Int? = nil
    public var restSeconds: Int? = nil
    public var note: String? = nil
}

public struct StrengthSessionTemplate: Codable, Equatable, Sendable {
    public var name: String
    public var focus: StrengthFocus
    public var slots: [ExerciseSlot]
}

public struct SetScheme: Codable, Equatable, Sendable {
    public var sets: Int
    public var repsLow: Int
    public var repsHigh: Int
    public var restSeconds: Int
}

public struct GoalPrescription: Codable, Equatable, Sendable {
    public var main: SetScheme
    public var accessory: SetScheme
}

public struct RepBand: Codable, Equatable, Sendable {
    public var repsLow: Int
    public var repsHigh: Int
}

public struct StrengthProgrammeFile: Codable, Equatable, Sendable {
    public var sessions: [String: StrengthSessionTemplate]
    public var splits: [String: [String]]
    public var prescriptions: [String: GoalPrescription]
    public var bodyweightReps: RepBand
    public var taperSetMultiplier: Double
    /// Optional; defaults to `ProgressionRules.standard`.
    public var progression: ProgressionRules?

    public var progressionRules: ProgressionRules { progression ?? .standard }
}

// MARK: - Plan rules

public struct GoalRules: Codable, Equatable, Sendable {
    public var runShare: Double
    public var minLifts: Int
    public var maxLifts: Int
    public var maxQuality: Int
    public var qualityOrder: [RunSessionType]
    public var taperWeeks: Int
    public var longRunCapMeters: Double
    public var longRunShare: Double
}

public struct PlanRules: Codable, Equatable, Sendable {
    public var goals: [String: GoalRules]
    public var quality: [String: [String: Int]]
    public var startVolumeMeters: [String: Double]
    public var peakVolumeMeters: [String: [String: Double]]
    public var maxRunMeters: [String: Double]
    public var minRunMeters: Double
    public var weeklyIncrease: [String: Double]
    public var maxWeeklyIncrease: Double
    public var recoveryWeekEvery: Int
    public var recoveryWeekFactor: Double
    public var taperFactors: [Double]
    public var rollingHorizonWeeks: Int
    public var plannedEffort: [String: Double]

    public func goal(_ goal: TrainingGoal) -> GoalRules {
        goals[goal.rawValue] ?? GoalRules(
            runShare: 0.5, minLifts: 1, maxLifts: 3, maxQuality: 1,
            qualityOrder: [.tempo, .intervals], taperWeeks: 1, longRunCapMeters: 12000, longRunShare: 0.3
        )
    }

    public func qualityCount(level: ExperienceLevel, phase: TrainingPhase) -> Int {
        quality[level.rawValue]?[phase.rawValue] ?? 1
    }

    public func effort(_ key: String) -> Double {
        plannedEffort[key] ?? 5
    }
}

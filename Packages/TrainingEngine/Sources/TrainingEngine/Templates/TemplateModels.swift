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

public struct ExerciseDefinition: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var pattern: String
    public var requires: Equipment
    public var loading: ExerciseLoading
    public var region: BodyRegion
    public var mainLift: MainLift?
    public var defaultWeightKg: [String: Double]?

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
    public var pattern: String
    public var role: SlotRole
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

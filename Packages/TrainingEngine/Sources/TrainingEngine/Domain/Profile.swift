import Foundation

public enum ExperienceLevel: String, Codable, CaseIterable, Sendable {
    case beginner, intermediate, advanced
}

public enum TrainingGoal: String, Codable, CaseIterable, Sendable {
    case first5k
    case faster10k
    case halfMarathon
    case marathon
    case buildStrength
    case buildMuscle
    case balancedHybrid

    /// True when the goal is primarily a running goal.
    public var isRunningFocused: Bool {
        switch self {
        case .first5k, .faster10k, .halfMarathon, .marathon: return true
        case .buildStrength, .buildMuscle, .balancedHybrid: return false
        }
    }
}

public enum Equipment: String, Codable, CaseIterable, Sendable {
    case fullGym, homeGym, dumbbellsOnly, bodyweight
}

public enum UnitSystem: String, Codable, CaseIterable, Sendable {
    /// Kilometres and kilograms.
    case metric
    /// Miles and pounds.
    case imperial
}

/// ISO-style weekday, Monday = 1 ... Sunday = 7.
public enum Weekday: Int, Codable, CaseIterable, Comparable, Sendable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    public var fullName: String {
        switch self {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }

    public var shortName: String {
        switch self {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }
}

/// A recent race result or comfortable time used to derive pace zones.
public struct RaceResult: Codable, Equatable, Sendable {
    public var distanceMeters: Double
    public var timeSeconds: Double

    public init(distanceMeters: Double, timeSeconds: Double) {
        self.distanceMeters = distanceMeters
        self.timeSeconds = timeSeconds
    }
}

public enum MainLift: String, Codable, CaseIterable, Sendable {
    case squat, deadlift, benchPress, overheadPress, row
}

/// A user's estimate for a main lift: either a working weight for reps, or a 1RM (reps == 1).
public struct LiftEstimate: Codable, Equatable, Sendable {
    public var lift: MainLift
    public var weightKg: Double
    public var reps: Int

    public init(lift: MainLift, weightKg: Double, reps: Int) {
        self.lift = lift
        self.weightKg = weightKg
        self.reps = reps
    }
}

/// Everything collected in onboarding: the input to plan generation.
public struct AthleteProfile: Codable, Equatable, Sendable {
    public var runningExperience: ExperienceLevel
    public var recentRace: RaceResult?
    public var liftingExperience: ExperienceLevel
    public var liftEstimates: [LiftEstimate]
    public var goal: TrainingGoal
    public var eventDate: Date?
    public var trainingDays: [Weekday]
    public var doubleSessionDays: Int
    public var equipment: Equipment
    public var units: UnitSystem

    public init(
        runningExperience: ExperienceLevel,
        recentRace: RaceResult? = nil,
        liftingExperience: ExperienceLevel,
        liftEstimates: [LiftEstimate] = [],
        goal: TrainingGoal,
        eventDate: Date? = nil,
        trainingDays: [Weekday],
        doubleSessionDays: Int = 0,
        equipment: Equipment,
        units: UnitSystem = .metric
    ) {
        self.runningExperience = runningExperience
        self.recentRace = recentRace
        self.liftingExperience = liftingExperience
        self.liftEstimates = liftEstimates
        self.goal = goal
        self.eventDate = eventDate
        self.trainingDays = trainingDays.sorted()
        self.doubleSessionDays = doubleSessionDays
        self.equipment = equipment
        self.units = units
    }
}

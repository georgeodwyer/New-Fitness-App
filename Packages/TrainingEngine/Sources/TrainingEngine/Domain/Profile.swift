import Foundation

public enum ExperienceLevel: String, Codable, CaseIterable, Sendable {
    case beginner, intermediate, advanced
}

public enum TrainingGoal: String, Codable, CaseIterable, Sendable {
    case first5k
    case faster5k
    case faster10k
    case halfMarathon
    case marathon
    case buildStrength
    case buildMuscle
    case balancedHybrid
    /// A Hyrox race: 8 × 1 km runs, each followed by a station.
    case hyrox

    /// True when the goal is primarily a running goal.
    public var isRunningFocused: Bool {
        switch self {
        case .first5k, .faster5k, .faster10k, .halfMarathon, .marathon, .hyrox: return true
        case .buildStrength, .buildMuscle, .balancedHybrid: return false
        }
    }
}

/// The Hyrox race category, which sets the station weights in gym sessions.
public enum HyroxDivision: String, Codable, CaseIterable, Sendable {
    case openWomen = "open-women", openMen = "open-men", proWomen = "pro-women", proMen = "pro-men"

    public var displayName: String {
        switch self {
        case .openWomen: return "Open \u{00B7} Women"
        case .openMen: return "Open \u{00B7} Men"
        case .proWomen: return "Pro \u{00B7} Women"
        case .proMen: return "Pro \u{00B7} Men"
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
    /// How far they run in a typical week now (nil = not asked or don't know; 0 = not running).
    public var weeklyRunMeters: Double?
    /// Their longest run in the last month.
    public var longestRecentRunMeters: Double?
    /// Raced in the two weeks before answering (nil = not asked).
    public var racedRecently: Bool?
    /// Wants an easy first week after that race, and when they said so.
    public var easyFirstWeek: Bool?
    public var easyFirstWeekRequestedAt: Date?
    /// Gym sessions a week and the split they chose (nil = let the plan decide, as before).
    public var liftSessionsPerWeek: Int?
    public var splitCode: String?
    /// Year of birth, from the age they gave (nil = not given). Sets max heart rate.
    public var birthYear: Int?
    /// Their own heart-rate zones, when they've edited them.
    public var heartRateZones: HeartRateZoneSettings?
    /// Hyrox race category (Hyrox goal only).
    public var hyroxDivision: HyroxDivision?
    /// Exercises the runner swapped for a gym day and kept: `swapKey(day:exerciseId:)` → the
    /// exercise used instead (e.g. "Push|barbell-bench-press" → "dumbbell-bench-press").
    public var exerciseSwaps: [String: String]?
    /// The day they chose to start their plan (nil = as soon as sensible: this Monday if it's
    /// early in the week, else next Monday).
    public var planStartDate: Date?

    public static func swapKey(day: String, exerciseId: String) -> String { "\(day)|\(exerciseId)" }

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
        units: UnitSystem = .metric,
        weeklyRunMeters: Double? = nil,
        longestRecentRunMeters: Double? = nil,
        racedRecently: Bool? = nil,
        easyFirstWeek: Bool? = nil,
        easyFirstWeekRequestedAt: Date? = nil,
        liftSessionsPerWeek: Int? = nil,
        splitCode: String? = nil,
        birthYear: Int? = nil,
        heartRateZones: HeartRateZoneSettings? = nil,
        hyroxDivision: HyroxDivision? = nil,
        exerciseSwaps: [String: String]? = nil,
        planStartDate: Date? = nil
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
        self.weeklyRunMeters = weeklyRunMeters
        self.longestRecentRunMeters = longestRecentRunMeters
        self.racedRecently = racedRecently
        self.easyFirstWeek = easyFirstWeek
        self.easyFirstWeekRequestedAt = easyFirstWeekRequestedAt
        self.liftSessionsPerWeek = liftSessionsPerWeek
        self.splitCode = splitCode
        self.birthYear = birthYear
        self.heartRateZones = heartRateZones
        self.hyroxDivision = hyroxDivision
        self.exerciseSwaps = exerciseSwaps
        self.planStartDate = planStartDate
    }

    /// Age this year (nil when not given).
    public func age(on date: Date = .now, calendar: Calendar = .current) -> Int? {
        birthYear.map { calendar.component(.year, from: date) - $0 }
    }
}

extension AthleteProfile {
    /// Plain-English names of the answers that differ from `other` and affect the plan
    /// (units don't: they only change how things are shown).
    public func planAffectingChanges(comparedTo other: AthleteProfile) -> [String] {
        var changes: [String] = []
        if goal != other.goal { changes.append("goal") }
        if eventDate.map({ Int($0.timeIntervalSince1970 / 86400) }) != other.eventDate.map({ Int($0.timeIntervalSince1970 / 86400) }) {
            changes.append("event date")
        }
        if Set(trainingDays) != Set(other.trainingDays) { changes.append("training days") }
        if doubleSessionDays != other.doubleSessionDays { changes.append("double sessions") }
        if equipment != other.equipment { changes.append("equipment") }
        if runningExperience != other.runningExperience { changes.append("running experience") }
        if liftingExperience != other.liftingExperience { changes.append("lifting experience") }
        if recentRace != other.recentRace { changes.append("race time") }
        if liftEstimates != other.liftEstimates { changes.append("lift numbers") }
        if planStartDate.map({ Int($0.timeIntervalSince1970 / 86400) }) != other.planStartDate.map({ Int($0.timeIntervalSince1970 / 86400) }) {
            changes.append("start date")
        }
        if weeklyRunMeters != other.weeklyRunMeters || longestRecentRunMeters != other.longestRecentRunMeters {
            changes.append("current running")
        }
        if racedRecently != other.racedRecently || easyFirstWeek != other.easyFirstWeek { changes.append("recent race") }
        if liftSessionsPerWeek != other.liftSessionsPerWeek || splitCode != other.splitCode { changes.append("gym week") }
        if hyroxDivision != other.hyroxDivision { changes.append("Hyrox division") }
        return changes
    }
}

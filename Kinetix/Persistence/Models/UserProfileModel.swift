import Foundation
import SwiftData
import TrainingEngine

/// The user's onboarding answers. One per account.
@Model
final class UserProfileModel: SyncTracked {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    var runningExperienceRaw: String
    var recentRaceData: Data?
    var liftingExperienceRaw: String
    var liftEstimatesData: Data
    var goalRaw: String
    var eventDate: Date?
    var trainingDaysData: Data
    var doubleSessionDays: Int
    var equipmentRaw: String
    var unitsRaw: String
    var createdAt: Date
    /// Typical weekly running and longest recent run when they answered (nil = not given).
    var weeklyRunMeters: Double?
    var longestRecentRunMeters: Double?
    /// Raced in the two weeks before answering, and whether they asked for an easy first week.
    var racedRecently: Bool?
    var easyFirstWeek: Bool?
    var easyFirstWeekRequestedAt: Date?
    /// Gym sessions a week and the split they chose (nil = not chosen; the app decides).
    var liftSessionsPerWeek: Int?
    var splitCode: String?
    /// Year of birth (from their age) and their own heart-rate zones, when set.
    var birthYear: Int?
    var heartRateZonesData: Data?
    /// Hyrox race category (Hyrox goal only).
    var hyroxDivisionRaw: String?
    /// Encoded `[String: String]`: exercises swapped for a gym day and kept.
    var exerciseSwapsData: Data?

    init(profile: AthleteProfile, id: UUID = UUID(), now: Date = .now) {
        self.id = id
        self.updatedAt = now
        self.deletedAt = nil
        self.needsSync = true
        self.runningExperienceRaw = profile.runningExperience.rawValue
        self.recentRaceData = profile.recentRace.map { StoredJSON.encode($0) }
        self.liftingExperienceRaw = profile.liftingExperience.rawValue
        self.liftEstimatesData = StoredJSON.encode(profile.liftEstimates)
        self.goalRaw = profile.goal.rawValue
        self.eventDate = profile.eventDate
        self.trainingDaysData = StoredJSON.encode(profile.trainingDays)
        self.doubleSessionDays = profile.doubleSessionDays
        self.equipmentRaw = profile.equipment.rawValue
        self.unitsRaw = profile.units.rawValue
        self.createdAt = now
        self.weeklyRunMeters = profile.weeklyRunMeters
        self.longestRecentRunMeters = profile.longestRecentRunMeters
        self.racedRecently = profile.racedRecently
        self.easyFirstWeek = profile.easyFirstWeek
        self.easyFirstWeekRequestedAt = profile.easyFirstWeekRequestedAt
        self.liftSessionsPerWeek = profile.liftSessionsPerWeek
        self.splitCode = profile.splitCode
        self.birthYear = profile.birthYear
        self.heartRateZonesData = profile.heartRateZones.map { StoredJSON.encode($0) }
        self.hyroxDivisionRaw = profile.hyroxDivision?.rawValue
        self.exerciseSwapsData = profile.exerciseSwaps.map { StoredJSON.encode($0) }
    }

    /// The engine's view of this profile.
    var profile: AthleteProfile {
        get {
            AthleteProfile(
                runningExperience: ExperienceLevel(rawValue: runningExperienceRaw) ?? .beginner,
                recentRace: StoredJSON.decode(RaceResult.self, from: recentRaceData),
                liftingExperience: ExperienceLevel(rawValue: liftingExperienceRaw) ?? .beginner,
                liftEstimates: StoredJSON.decode([LiftEstimate].self, from: liftEstimatesData) ?? [],
                goal: TrainingGoal(rawValue: goalRaw) ?? .balancedHybrid,
                eventDate: eventDate,
                trainingDays: StoredJSON.decode([Weekday].self, from: trainingDaysData) ?? [],
                doubleSessionDays: doubleSessionDays,
                equipment: Equipment(rawValue: equipmentRaw) ?? .fullGym,
                units: UnitSystem(rawValue: unitsRaw) ?? .metric,
                weeklyRunMeters: weeklyRunMeters,
                longestRecentRunMeters: longestRecentRunMeters,
                racedRecently: racedRecently,
                easyFirstWeek: easyFirstWeek,
                easyFirstWeekRequestedAt: easyFirstWeekRequestedAt,
                liftSessionsPerWeek: liftSessionsPerWeek,
                splitCode: splitCode,
                birthYear: birthYear,
                heartRateZones: StoredJSON.decode(HeartRateZoneSettings.self, from: heartRateZonesData),
                hyroxDivision: hyroxDivisionRaw.flatMap(HyroxDivision.init(rawValue:)),
                exerciseSwaps: StoredJSON.decode([String: String].self, from: exerciseSwapsData)
            )
        }
        set {
            runningExperienceRaw = newValue.runningExperience.rawValue
            recentRaceData = newValue.recentRace.map { StoredJSON.encode($0) }
            liftingExperienceRaw = newValue.liftingExperience.rawValue
            liftEstimatesData = StoredJSON.encode(newValue.liftEstimates)
            goalRaw = newValue.goal.rawValue
            eventDate = newValue.eventDate
            trainingDaysData = StoredJSON.encode(newValue.trainingDays)
            doubleSessionDays = newValue.doubleSessionDays
            equipmentRaw = newValue.equipment.rawValue
            unitsRaw = newValue.units.rawValue
            weeklyRunMeters = newValue.weeklyRunMeters
            longestRecentRunMeters = newValue.longestRecentRunMeters
            racedRecently = newValue.racedRecently
            easyFirstWeek = newValue.easyFirstWeek
            easyFirstWeekRequestedAt = newValue.easyFirstWeekRequestedAt
            liftSessionsPerWeek = newValue.liftSessionsPerWeek
            splitCode = newValue.splitCode
            birthYear = newValue.birthYear
            heartRateZonesData = newValue.heartRateZones.map { StoredJSON.encode($0) }
            hyroxDivisionRaw = newValue.hyroxDivision?.rawValue
            exerciseSwapsData = newValue.exerciseSwaps.map { StoredJSON.encode($0) }
            touch()
        }
    }

    var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }
}

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
                units: UnitSystem(rawValue: unitsRaw) ?? .metric
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
            touch()
        }
    }

    var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }
}

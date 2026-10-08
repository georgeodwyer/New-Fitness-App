import Foundation
import SwiftData
import TrainingEngine

/// Development sample data: a typical profile run through the real plan generator.
enum SampleData {
    static let profile = AthleteProfile(
        runningExperience: .intermediate,
        recentRace: RaceResult(distanceMeters: 5000, timeSeconds: 22 * 60 + 30),
        liftingExperience: .intermediate,
        liftEstimates: [LiftEstimate(lift: .squat, weightKg: 100, reps: 8)],
        goal: .halfMarathon,
        eventDate: Calendar.current.date(byAdding: .weekOfYear, value: 12, to: .now),
        trainingDays: [.monday, .tuesday, .wednesday, .friday, .saturday, .sunday],
        doubleSessionDays: 1,
        equipment: .fullGym,
        units: .metric
    )

    /// Inserts the sample profile, default coaching settings and a generated plan.
    @MainActor
    static func seed(into context: ModelContext, now: Date = .now) {
        context.insert(UserProfileModel(profile: profile))
        context.insert(CoachingSettingsModel())
        PlanService.createPlan(for: profile, in: context, now: now)
    }

    /// Deletes everything (development reset).
    @MainActor
    static func eraseAll(in context: ModelContext) {
        try? context.delete(model: PlannedSessionModel.self)
        try? context.delete(model: TrainingPlanModel.self)
        try? context.delete(model: PlanChangeModel.self)
        try? context.delete(model: SetLogModel.self)
        try? context.delete(model: StrengthLogModel.self)
        try? context.delete(model: RunLogModel.self)
        try? context.delete(model: ExerciseStateModel.self)
        try? context.delete(model: PersonalRecordModel.self)
        try? context.delete(model: RecoveryCheckInModel.self)
        try? context.delete(model: CoachingSettingsModel.self)
        try? context.delete(model: UserProfileModel.self)
        try? context.save()
    }
}

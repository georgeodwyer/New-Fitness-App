import Foundation
import SwiftData
import TrainingEngine

/// Development sample data so screens have something to show before the plan
/// engine exists (Milestone 2 replaces this with real generation).
enum SampleData {
    static let profile = AthleteProfile(
        runningExperience: .intermediate,
        recentRace: RaceResult(distanceMeters: 5000, timeSeconds: 22 * 60 + 30),
        liftingExperience: .intermediate,
        liftEstimates: [LiftEstimate(lift: .squat, weightKg: 100, reps: 8)],
        goal: .halfMarathon,
        eventDate: Calendar.current.date(byAdding: .weekOfYear, value: 12, to: .now),
        trainingDays: [.monday, .tuesday, .wednesday, .friday, .saturday],
        doubleSessionDays: 1,
        equipment: .fullGym,
        units: .metric
    )

    /// Inserts a profile, default coaching settings and a week of sample sessions.
    @MainActor
    static func seed(into context: ModelContext, now: Date = .now) {
        context.insert(UserProfileModel(profile: profile))
        context.insert(CoachingSettingsModel())

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let plan = TrainingPlanModel(goal: profile.goal, startDate: today, endDate: profile.eventDate)
        context.insert(plan)

        let tempoZone = PaceRange(fastest: Pace(secondsPerKm: 265), slowest: Pace(secondsPerKm: 275))
        let week: [(Int, SessionSlot, SessionKind, Bool, Double, Double)] = [
            (0, .morning, .run(.tempo), true, 45, 7),
            (0, .evening, .strength(.upper), false, 50, 7),
            (1, .morning, .run(.easy), false, 40, 3),
            (2, .morning, .strength(.lower), false, 55, 8),
            (4, .morning, .run(.intervals), true, 50, 8),
            (5, .morning, .run(.long), true, 95, 6)
        ]
        for (offset, slot, kind, isKey, minutes, effort) in week {
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            var structure: RunStructure?
            if case .run(let type) = kind, type == .tempo {
                structure = RunStructure(segments: [
                    RunSegment(kind: .warmUp, length: .duration(seconds: 600)),
                    RunSegment(kind: .work, length: .distance(meters: 5000), targetPace: tempoZone),
                    RunSegment(kind: .coolDown, length: .duration(seconds: 600))
                ])
            }
            var strength: StrengthPrescription?
            if case .strength = kind {
                strength = StrengthPrescription(exercises: [
                    ExercisePrescription(exerciseId: "barbell-back-squat", sets: 4, repRange: RepRange(6, 8), weightKg: 100, restSeconds: 150)
                ])
            }
            let session = PlannedSessionModel(
                date: date,
                slot: slot,
                kind: kind,
                isKey: isKey,
                plannedDurationMinutes: minutes,
                plannedEffort: effort,
                runStructure: structure,
                strength: strength
            )
            session.plan = plan
            context.insert(session)
        }
        try? context.save()
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

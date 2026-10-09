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

    /// Inserts the sample profile, default coaching settings and a generated plan that
    /// started this Monday (so the current week is populated for demos and screenshots).
    @MainActor
    static func seed(into context: ModelContext, now: Date = .now) {
        context.insert(UserProfileModel(profile: profile))
        context.insert(CoachingSettingsModel())
        let monday = Calendar.kinetix.startOfISOWeek(for: now)
        let plan = PlanService.createPlan(for: profile, in: context, now: monday)
        // Generate the rest of the horizon relative to today.
        PlanService.ensureHorizon(for: plan, profile: profile, in: context, now: now)
        try? context.save()
    }

    /// Adds ~4 weeks of past runs, lifts, records and a check-in so the dashboard
    /// has something to show (screenshots and demos).
    @MainActor
    static func seedHistory(into context: ModelContext, now: Date = .now) {
        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: now)
        var random = SeededRandom(seed: 11)
        for offset in 1...28 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = calendar.weekday(of: day)
            guard profile.trainingDays.contains(weekday) else { continue }
            let build = 1 + Double(28 - offset) / 60 // load creeps up over the month
            if weekday != .wednesday {
                let minutes = (weekday == .sunday ? 80 : 42) * build
                let run = RunLogModel(plannedSessionId: nil, startedAt: day.addingTimeInterval(7 * 3600))
                run.title = weekday == .sunday ? "Long Run" : "Easy Run"
                run.durationSeconds = minutes * 60
                run.distanceMeters = minutes * 60 / 340 * 1000
                run.effort = weekday == .sunday ? 6 : 3 + Double(Int(random.next() * 3))
                run.load = minutes * run.effort
                run.isFinished = true
                run.finishedAt = run.startedAt.addingTimeInterval(run.durationSeconds)
                context.insert(run)
            }
            if weekday == .monday || weekday == .wednesday || weekday == .friday {
                let lift = StrengthLogModel(plannedSessionId: nil, startedAt: day.addingTimeInterval(18 * 3600))
                lift.title = weekday == .wednesday ? "Lower Body" : "Upper Body"
                lift.durationSeconds = 55 * 60
                lift.effort = 7
                lift.load = 55 * 7 * build
                lift.isFinished = true
                lift.finishedAt = lift.startedAt.addingTimeInterval(lift.durationSeconds)
                context.insert(lift)
                for set in 0..<4 {
                    let weight = 90 + Double(28 - offset) / 7 * 2.5
                    let log = SetLogModel(exerciseId: "barbell-back-squat", setIndex: set, targetReps: 8, targetWeightKg: weight)
                    log.exerciseName = "Barbell Back Squat"
                    log.progressionKey = "barbell-back-squat.main"
                    log.repRangeLower = 6
                    log.repRangeUpper = 8
                    log.completedAt = lift.startedAt
                    context.insert(log)
                    log.session = lift
                }
            }
        }
        // This week's sessions before today: mostly done, one skipped, to make the week realistic.
        let planned = (try? context.fetch(FetchDescriptor<PlannedSessionModel>())) ?? []
        let earlier = planned.filter { $0.date < today && $0.date >= calendar.startOfISOWeek(for: today) }.sorted { $0.date < $1.date }
        for (index, session) in earlier.enumerated() {
            session.status = index == 1 ? .skipped : .completed
        }
        context.insert(PersonalRecordModel(recordKey: "barbell-back-squat", kindRaw: RecordKind.estimatedOneRepMax.rawValue,
                                           value: 125, achievedAt: today.addingTimeInterval(-2 * 86400)))
        context.insert(PersonalRecordModel(recordKey: "barbell-bench-press", kindRaw: RecordKind.estimatedOneRepMax.rawValue,
                                           value: 82.5, achievedAt: today.addingTimeInterval(-5 * 86400)))
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

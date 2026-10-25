import Foundation
import SwiftData
import TrainingEngine

/// Bridges the training engine and the database: creates plans from a profile and
/// keeps detailed sessions generated about two weeks ahead.
@MainActor
enum PlanService {
    /// How far ahead detailed sessions are kept.
    static let horizonDays = 14

    static let templates: TemplateLibrary = {
        do {
            return try TemplateLibrary.bundled()
        } catch {
            // The templates ship inside the app; failing to load them is a build error.
            fatalError("Training templates failed to load: \(error)")
        }
    }()

    static var generator: PlanGenerator { PlanGenerator(templates: templates) }

    /// A plan preview that isn't saved (used at the end of onboarding).
    struct Preview {
        var outline: PlanOutline
        var firstWeek: GeneratedWeek?
        var zones: PaceZones
    }

    static func preview(for profile: AthleteProfile, now: Date = .now) -> Preview {
        let generator = generator
        let outline = generator.makeOutline(for: profile, startingOn: generator.planStart(from: now))
        let firstWeek = generator.generateWeek(0, outline: outline, profile: profile, notBefore: now)
        return Preview(outline: outline, firstWeek: firstWeek, zones: PaceZones(profile: profile))
    }

    /// Replaces the active plan with a freshly generated one. Completed sessions and
    /// logs are kept; future planned sessions of the old plan are removed.
    @discardableResult
    static func createPlan(for profile: AthleteProfile, in context: ModelContext, now: Date = .now) -> TrainingPlanModel {
        let today = Calendar.kinetix.startOfDay(for: now)
        let existing = (try? context.fetch(FetchDescriptor<TrainingPlanModel>())) ?? []
        for plan in existing where plan.isActive {
            plan.isActive = false
            plan.touch(now: now)
            for session in plan.sessions where session.status == .planned && session.date >= today {
                session.softDelete(now: now)
            }
        }

        let generator = generator
        let outline = generator.makeOutline(for: profile, startingOn: generator.planStart(from: now))
        let plan = TrainingPlanModel(goal: profile.goal, startDate: outline.startDate, endDate: outline.eventDate)
        plan.outline = outline
        context.insert(plan)
        context.insert(PlanChangeModel(summary: "Created a new \(outline.weeks.count)-week plan for \(profile.goal.displayName.lowercased()).", now: now))

        ensureHorizon(for: plan, profile: profile, in: context, now: now)
        try? context.save()
        SyncService.shared.requestSync()
        return plan
    }

    /// Generates further weeks so sessions always exist about two weeks ahead.
    static func ensureHorizon(for plan: TrainingPlanModel, profile: AthleteProfile, in context: ModelContext, now: Date = .now) {
        guard var outline = plan.outline else { return }
        let calendar = Calendar.kinetix
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: calendar.startOfDay(for: now)) ?? now
        let generator = generator
        // A coach's programme repeats: once its last week is within reach, add the next time
        // through, starting from what they've actually been running.
        if let last = outline.weeks.last, last.startDate <= horizon,
           let next = generator.nextCycle(of: outline, profile: profile, recentWeeklyRunMeters: recentWeeklyRunMeters(in: context, now: now)) {
            outline = next
            plan.outline = next
            context.insert(PlanChangeModel(summary: "Your programme starts again after the recovery week, from the running you've been doing.", now: now))
        }
        let weights = workingWeights(in: context)

        while plan.generatedWeekCount < outline.weeks.count,
              outline.weeks[plan.generatedWeekCount].startDate <= horizon {
            let index = plan.generatedWeekCount
            if let week = generator.generateWeek(index, outline: outline, profile: profile, workingWeights: weights, notBefore: now) {
                for generated in week.sessions {
                    let session = PlannedSessionModel(generated: generated, weekIndex: index)
                    context.insert(session)
                    session.plan = plan
                    registerExercises(generated.strength, in: context, existing: weights)
                }
                // The coach's notes show on the week in the Plan tab (not in the change log).
                plan.setNotes(week.notes, forWeek: index)
            }
            plan.generatedWeekCount += 1
            plan.touch(now: now)
        }
    }

    /// Show the whole plan on the Plan tab, with weeks beyond the horizon as previews.
    /// For launch, set this to false to show only the weeks already built (week by week).
    static let showsWholePlan = true

    /// The weeks not built yet, as they'd be generated today (not saved: they can still
    /// change with progress, and become real sessions about two weeks out).
    static func previewWeeks(for plan: TrainingPlanModel, profile: AthleteProfile, in context: ModelContext,
                             now: Date = .now) -> [Int: GeneratedWeek] {
        guard showsWholePlan, let outline = plan.outline, plan.generatedWeekCount < outline.weeks.count else { return [:] }
        let generator = generator
        let weights = workingWeights(in: context)
        var weeks: [Int: GeneratedWeek] = [:]
        for index in plan.generatedWeekCount..<outline.weeks.count {
            if let week = generator.generateWeek(index, outline: outline, profile: profile, workingWeights: weights, notBefore: now) {
                weeks[index] = week
            }
        }
        return weeks
    }

    /// Tops up the active plan's horizon (call on launch / foreground).
    static func refresh(in context: ModelContext, now: Date = .now) {
        guard let profileModel = try? context.fetch(FetchDescriptor<UserProfileModel>()).first(where: { !$0.isSoftDeleted }),
              let plan = try? context.fetch(FetchDescriptor<TrainingPlanModel>()).first(where: { $0.isActive && !$0.isSoftDeleted })
        else { return }
        let before = plan.generatedWeekCount
        ensureHorizon(for: plan, profile: profileModel.profile, in: context, now: now)
        if plan.generatedWeekCount != before { try? context.save() }
    }

    /// Average weekly running over the last four weeks (nil if nothing was recorded).
    static func recentWeeklyRunMeters(in context: ModelContext, now: Date = .now) -> Double? {
        recentRunning(in: context, now: now)?.weeklyMeters
    }

    /// The last four weeks of running: runs recorded in Kinetix or imported from Strava, plus
    /// other apps' runs in Apple Health (copies of the same run counted once).
    static func recentRunning(in context: ModelContext, now: Date = .now) -> RecentRunning.Summary? {
        let logs = ((try? context.fetch(FetchDescriptor<RunLogModel>())) ?? [])
            .filter { !$0.isSoftDeleted && $0.isFinished && !$0.usedSimulatedGPS }
            .map { RecentRunning.Run(start: $0.startedAt, meters: $0.distanceMeters) }
        let settings = IntegrationSettings.shared
        let health = (settings.healthEnabled ? settings.externalWorkouts : [])
            .filter { $0.kind == .run }
            .compactMap { workout in workout.distanceMeters.map { RecentRunning.Run(start: workout.start, meters: $0) } }
        return RecentRunning.summary(RecentRunning.merge(primary: logs, other: health), now: now)
    }

    /// The runner entered (or changed) numbers for their main lifts: those lifts' working
    /// weights start again from the numbers, in the saved weights and the sessions already
    /// built. Lifts without numbers keep progressing from what they've logged.
    static func applyLiftEstimates(_ estimates: [LiftEstimate], profile: AthleteProfile, in context: ModelContext, now: Date = .now) {
        let byLift = Dictionary(estimates.filter { $0.weightKg > 0 }.map { ($0.lift, $0) }, uniquingKeysWith: { _, last in last })
        guard !byLift.isEmpty else { return }
        let library = templates
        func match(_ exerciseId: String) -> (estimate: LiftEstimate, exercise: ExerciseDefinition)? {
            guard let exercise = library.exercise(id: exerciseId), let lift = exercise.mainLift, let estimate = byLift[lift] else { return nil }
            return (estimate, exercise)
        }
        var weights: [String: Double] = [:]

        // Sessions already built for the coming weeks.
        let today = Calendar.kinetix.startOfDay(for: now)
        let sessions = ((try? context.fetch(FetchDescriptor<PlannedSessionModel>())) ?? []).filter {
            !$0.isSoftDeleted && $0.date >= today && ($0.status == .planned || $0.status == .swapped) && ($0.plan?.isActive ?? true)
        }
        for session in sessions {
            guard var prescription = session.strengthPrescription else { continue }
            var changed = false
            for index in prescription.exercises.indices {
                let item = prescription.exercises[index]
                guard item.weightKg != nil, let found = match(item.exerciseId) else { continue }
                let weight = StrengthMath.weight(from: found.estimate, reps: item.repRange.lower, accessory: item.role == .accessory,
                                                 loading: found.exercise.loading)
                prescription.exercises[index].weightKg = weight
                weights[item.progressionKey] = weights[item.progressionKey] ?? weight
                changed = true
            }
            if changed {
                session.strengthPrescriptionData = StoredJSON.encode(prescription)
                session.touch(now: now)
            }
        }

        // Saved working weights (used for every week built from now on).
        let goal = library.prescription(for: profile.goal)
        let states = ((try? context.fetch(FetchDescriptor<ExerciseStateModel>())) ?? []).filter { !$0.isSoftDeleted }
        for state in states {
            guard let found = match(state.exerciseId) else { continue }
            let accessory = state.progressionKey.hasSuffix(".accessory")
            let reps = (accessory ? goal?.accessory.repsLow : goal?.main.repsLow) ?? state.repRangeLower
            let weight = weights[state.progressionKey]
                ?? StrengthMath.weight(from: found.estimate, reps: max(reps, 1), accessory: accessory, loading: found.exercise.loading)
            guard weight != state.workingWeightKg else { continue }
            state.workingWeightKg = weight
            state.stallCount = 0
            state.lastChangeReason = "Set from your lift numbers"
            state.lastChangedAt = now
            state.touch(now: now)
        }
        try? context.save()
        SyncService.shared.requestSync()
    }

    /// Current working weights by progression key.
    static func workingWeights(in context: ModelContext) -> [String: Double] {
        let states = (try? context.fetch(FetchDescriptor<ExerciseStateModel>())) ?? []
        return Dictionary(states.filter { !$0.isSoftDeleted }.map { ($0.progressionKey, $0.workingWeightKg) },
                          uniquingKeysWith: { first, _ in first })
    }

    /// Records starting weights for exercises seen for the first time.
    private static func registerExercises(_ prescription: StrengthPrescription?, in context: ModelContext, existing: [String: Double]) {
        guard let prescription else { return }
        for exercise in prescription.exercises {
            guard let weight = exercise.weightKg, existing[exercise.progressionKey] == nil else { continue }
            let key = exercise.progressionKey
            let descriptor = FetchDescriptor<ExerciseStateModel>(predicate: #Predicate { $0.progressionKey == key })
            if let count = try? context.fetchCount(descriptor), count > 0 { continue }
            context.insert(ExerciseStateModel(
                progressionKey: key,
                exerciseId: exercise.exerciseId,
                workingWeightKg: weight,
                repRangeLower: exercise.repRange.lower,
                repRangeUpper: exercise.repRange.upper
            ))
        }
    }

    /// Puts a completed planned session back to "planned" (when the log that completed it is deleted).
    static func reopen(sessionId: UUID?, in context: ModelContext) {
        guard let sessionId,
              let session = try? context.fetch(FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.id == sessionId })).first,
              session.status == .completed else { return }
        session.status = .planned
        session.touch()
    }
}

extension TrainingGoal {
    var displayName: String {
        switch self {
        case .first5k: return "First 5K"
        case .faster5k: return "Faster 5K"
        case .faster10k: return "Faster 10K"
        case .halfMarathon: return "Half marathon"
        case .marathon: return "Marathon"
        case .buildStrength: return "Build strength"
        case .buildMuscle: return "Build muscle"
        case .balancedHybrid: return "Balanced hybrid fitness"
        case .hyrox: return "Hyrox"
        }
    }
}

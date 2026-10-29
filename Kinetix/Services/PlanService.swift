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
        let outline = generator.makeOutline(for: profile, startingOn: generator.planStart(from: now, requested: profile.planStartDate))
        let firstWeek = generator.generateWeek(0, outline: outline, profile: profile,
                                               notBefore: generator.firstSessionDay(from: now, requested: profile.planStartDate))
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
        let outline = generator.makeOutline(for: profile, startingOn: generator.planStart(from: now, requested: profile.planStartDate))
        // A chosen start day mid-week: the plan (and Today's "Plan starts …") begins that day.
        let firstDay = generator.firstSessionDay(from: now, requested: profile.planStartDate)
        let plan = TrainingPlanModel(goal: profile.goal, startDate: max(outline.startDate, firstDay), endDate: outline.eventDate)
        plan.outline = outline
        context.insert(plan)
        context.insert(PlanChangeModel(summary: "Created a new \(outline.weeks.count)-week plan for \(profile.goal.displayName.lowercased()).", now: now))

        ensureHorizon(for: plan, profile: profile, in: context, now: now)
        try? context.save()
        SyncService.shared.requestSync()
        return plan
    }

    // MARK: Pause

    enum PauseReason: String, CaseIterable, Identifiable {
        case ill, injured, away, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .ill: return "Ill"
            case .injured: return "Injured"
            case .away: return "Away"
            case .other: return "Something else"
            }
        }
        /// Coming back from these, the first week is an easier one.
        var easesBackIn: Bool { self == .ill || self == .injured }
    }

    /// Pauses the active plan: today's and later sessions are cleared until they resume.
    static func pause(reason: PauseReason, until: Date?, in context: ModelContext, now: Date = .now) {
        guard let plan = activePlan(in: context), !plan.isPaused else { return }
        let today = Calendar.kinetix.startOfDay(for: now)
        for session in plan.sessions where !session.isSoftDeleted && session.date >= today
            && (session.status == .planned || session.status == .swapped) {
            session.softDelete(now: now)
        }
        plan.pausedAt = now
        plan.pauseReasonRaw = reason.rawValue
        plan.pauseUntil = until
        plan.touch(now: now)
        context.insert(PlanChangeModel(summary: "Paused your plan (\(reason.title.lowercased())). Take the time you need; it picks up where you left off.", now: now))
        try? context.save()
        SyncService.shared.requestSync()
    }

    /// Picks the plan back up: from the week they paused in, moved later by the time away (an
    /// easier first week after illness or injury). With a race date, rebuilt around the race.
    static func resume(profile: AthleteProfile, in context: ModelContext, now: Date = .now) {
        guard let plan = activePlan(in: context), let pausedAt = plan.pausedAt, let outline = plan.outline else { return }
        let calendar = Calendar.kinetix
        let reason = plan.pauseReasonRaw.flatMap(PauseReason.init(rawValue:)) ?? .other
        let pausedMonday = calendar.startOfISOWeek(for: pausedAt)
        let thisMonday = calendar.startOfISOWeek(for: now)
        let weeksAway = max(0, (calendar.dateComponents([.day], from: pausedMonday, to: thisMonday).day ?? 0) / 7)
        let daysAway = calendar.dateComponents([.day], from: pausedAt, to: now).day ?? 0
        plan.pausedAt = nil
        plan.pauseReasonRaw = nil
        plan.pauseUntil = nil

        if outline.eventDate != nil {
            // The race doesn't move: rebuild the weeks left around it.
            rebuildRemainder(for: profile, in: context, now: now)
        } else {
            let pausedWeek = outline.weekIndex(containing: pausedAt, calendar: calendar) ?? plan.generatedWeekCount
            plan.outline = outline.resumed(fromWeek: pausedWeek, laterBy: weeksAway,
                                           easeFirstWeek: reason.easesBackIn && daysAway >= 7, calendar: calendar)
            plan.generatedWeekCount = min(pausedWeek, plan.generatedWeekCount)
            // Anything still planned from the paused week on is built again at its new dates.
            for session in plan.sessions where !session.isSoftDeleted && session.weekIndex >= pausedWeek
                && (session.status == .planned || session.status == .swapped) {
                session.softDelete(now: now)
            }
            ensureHorizon(for: plan, profile: profile, in: context, now: now)
        }
        let back = reason.easesBackIn && daysAway >= 7 ? " Your first week back is an easier one." : ""
        context.insert(PlanChangeModel(summary: "Welcome back! Your plan picks up where you left off.\(back)", now: now))
        plan.touch(now: now)
        try? context.save()
        SyncService.shared.requestSync()
    }

    static func activePlan(in context: ModelContext) -> TrainingPlanModel? {
        ((try? context.fetch(FetchDescriptor<TrainingPlanModel>())) ?? []).first { $0.isActive && !$0.isSoftDeleted }
    }

    /// Starts a plan the athlete built themselves (the current one stops, keeping what's done).
    @discardableResult
    static func createCustomPlan(_ custom: CustomPlan, profile: AthleteProfile, in context: ModelContext, now: Date = .now) -> TrainingPlanModel {
        let today = Calendar.kinetix.startOfDay(for: now)
        for plan in (try? context.fetch(FetchDescriptor<TrainingPlanModel>())) ?? [] where plan.isActive {
            plan.isActive = false
            plan.touch(now: now)
            for session in plan.sessions where session.status == .planned && session.date >= today {
                session.softDelete(now: now)
            }
        }
        let outline = generator.makeOutline(for: custom)
        let plan = TrainingPlanModel(goal: profile.goal, startDate: max(outline.startDate, today), endDate: outline.eventDate)
        plan.outline = outline
        context.insert(plan)
        context.insert(PlanChangeModel(summary: "Started your own plan, \(custom.name): \(custom.weeks) weeks.", now: now))
        ensureHorizon(for: plan, profile: profile, in: context, now: now)
        try? context.save()
        SyncService.shared.requestSync()
        return plan
    }

    /// Updates a self-built plan's template; the change starts next Monday, this week stays.
    static func updateCustomPlan(_ custom: CustomPlan, profile: AthleteProfile, in context: ModelContext, now: Date = .now) {
        let plans = ((try? context.fetch(FetchDescriptor<TrainingPlanModel>())) ?? []).filter { $0.isActive && !$0.isSoftDeleted }
        guard let plan = plans.first, var outline = plan.outline else {
            createCustomPlan(custom, profile: profile, in: context, now: now)
            return
        }
        outline.customPlan = custom
        plan.outline = outline
        rebuildRemainder(for: profile, in: context, now: now, startingNextWeek: true)
    }

    /// The self-built plan behind the active plan, if it is one.
    static func activeCustomPlan(in context: ModelContext) -> CustomPlan? {
        ((try? context.fetch(FetchDescriptor<TrainingPlanModel>())) ?? []).first { $0.isActive && !$0.isSoftDeleted }?.outline?.customPlan
    }

    /// Rebuilds the active plan from today with the current answers and the latest plan logic,
    /// keeping its start date and week numbers: sessions done or skipped stay, and today's and
    /// later sessions are built again. Falls back to a new plan if there isn't one.
    @discardableResult
    static func rebuildRemainder(for profile: AthleteProfile, in context: ModelContext, now: Date = .now,
                                 startingNextWeek: Bool = false) -> TrainingPlanModel {
        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: now)
        // From next Monday: this week stays exactly as it is (sessions not done yet included).
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: calendar.startOfISOWeek(for: today)) ?? today
        let from = startingNextWeek ? nextMonday : today
        let plans = ((try? context.fetch(FetchDescriptor<TrainingPlanModel>())) ?? []).filter { $0.isActive && !$0.isSoftDeleted }
        guard let plan = plans.first, let old = plan.outline, let firstMonday = old.weeks.first?.startDate else {
            return createPlan(for: profile, in: context, now: now)
        }
        let generator = generator
        // A plan they built themselves keeps its own weeks (only paces and weights are refreshed).
        let outline = old.customPlan.map { generator.makeOutline(for: $0) } ?? generator.makeOutline(for: profile, startingOn: firstMonday)
        // Past the end of the rebuilt plan (or before it starts): nothing to keep, start afresh.
        guard let current = outline.weekIndex(containing: from, calendar: calendar) ?? (from < firstMonday ? 0 : nil) else {
            return createPlan(for: profile, in: context, now: now)
        }
        for session in plan.sessions where !session.isSoftDeleted && session.date >= from
            && (session.status == .planned || session.status == .swapped) {
            session.softDelete(now: now)
        }
        plan.outline = outline
        plan.goalRaw = profile.goal.rawValue
        plan.engineVersion = TrainingEngine.version
        plan.endDate = outline.eventDate
        plan.generatedWeekCount = current

        // From `from` (today or next Monday); the following weeks as usual.
        let weights = workingWeights(in: context)
        let horizon = max(calendar.date(byAdding: .day, value: horizonDays, to: today) ?? today, from)
        while !plan.isPaused, plan.generatedWeekCount < outline.weeks.count, outline.weeks[plan.generatedWeekCount].startDate <= horizon {
            let index = plan.generatedWeekCount
            if let week = generator.generateWeek(index, outline: outline, profile: profile, workingWeights: weights, notBefore: from) {
                for generated in week.sessions {
                    let session = PlannedSessionModel(generated: generated, weekIndex: index)
                    context.insert(session)
                    session.plan = plan
                    registerExercises(generated.strength, in: context, existing: weights)
                }
                plan.setNotes(week.notes, forWeek: index)
            }
            plan.generatedWeekCount += 1
        }
        plan.touch(now: now)
        previewCache = nil
        let summary = startingNextWeek
            ? "Your updated plan starts Monday \(from.formatted(.dateTime.day().month())) (week \(current + 1) of \(outline.weeks.count)). This week stays as it was."
            : "Rebuilt your plan from today (week \(current + 1) of \(outline.weeks.count)). What you've done is kept."
        context.insert(PlanChangeModel(summary: summary, now: now))
        try? context.save()
        SyncService.shared.requestSync()
        return plan
    }

    /// Generates further weeks so sessions always exist about two weeks ahead.
    static func ensureHorizon(for plan: TrainingPlanModel, profile: AthleteProfile, in context: ModelContext, now: Date = .now) {
        guard var outline = plan.outline, !plan.isPaused else { return }
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
            if let week = generator.generateWeek(index, outline: outline, profile: profile, workingWeights: weights,
                                                notBefore: generator.firstSessionDay(from: now, requested: profile.planStartDate)) {
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
            if let week = generator.generateWeek(index, outline: outline, profile: profile, workingWeights: weights,
                                                notBefore: generator.firstSessionDay(from: now, requested: profile.planStartDate)) {
                weeks[index] = week
            }
        }
        return weeks
    }

    /// The last previews built, so opening the calendar or Plan tab again is instant.
    private static var previewCache: (key: String, weeks: [Int: GeneratedWeek])?

    /// The same as `previewWeeks`, built away from the main thread (a long plan takes
    /// seconds) and kept until the plan, its built weeks, the profile or the day change.
    static func previewWeeksInBackground(for plan: TrainingPlanModel, profile: AthleteProfile, in context: ModelContext,
                                         now: Date = .now) async -> [Int: GeneratedWeek] {
        guard showsWholePlan, let outline = plan.outline, plan.generatedWeekCount < outline.weeks.count else { return [:] }
        let profileData = (try? JSONEncoder().encode(profile)) ?? Data()
        let day = Calendar.kinetix.startOfDay(for: now).timeIntervalSince1970
        let weights = workingWeights(in: context)
        let key = "\(plan.id)-\(plan.generatedWeekCount)-\(profileData.hashValue)-\(day)-\(weights.count)"
        if let cached = previewCache, cached.key == key { return cached.weeks }
        let generator = generator
        let start = plan.generatedWeekCount
        let notBefore = generator.firstSessionDay(from: now, requested: profile.planStartDate)
        let weeks = await Task.detached(priority: .userInitiated) { () -> [Int: GeneratedWeek] in
            var result: [Int: GeneratedWeek] = [:]
            for index in start..<outline.weeks.count {
                if let week = generator.generateWeek(index, outline: outline, profile: profile, workingWeights: weights, notBefore: notBefore) {
                    result[index] = week
                }
            }
            return result
        }.value
        previewCache = (key, weeks)
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

    /// The runner entered (or changed) their lift numbers: main lifts and the variations linked
    /// to them start again from the numbers, in the saved weights, the sessions already built
    /// and any workout they've opened but not finished. Machines they've never logged go back
    /// to "pick a weight". Everything else keeps progressing from what they've logged.
    static func applyLiftEstimates(_ estimates: [LiftEstimate], profile: AthleteProfile, in context: ModelContext, now: Date = .now) {
        let estimates = estimates.filter { $0.weightKg > 0 }
        let library = templates
        let goal = library.prescription(for: profile.goal)
        // Machines without a default weight that they've never logged.
        let logged = Set(((try? context.fetch(FetchDescriptor<SetLogModel>())) ?? [])
            .filter { !$0.isSoftDeleted && $0.isCompleted && $0.actualWeightKg > 0 }
            .map(\.exerciseId))
        func target(_ exerciseId: String, reps: Int, accessory: Bool) -> Double? {
            guard let exercise = library.exercise(id: exerciseId) else { return nil }
            if let weight = StrengthMath.weight(for: exercise, estimates: estimates, reps: max(reps, 1), accessory: accessory) {
                return weight
            }
            if exercise.loading == .machine, exercise.defaultWeightKg == nil, !logged.contains(exerciseId) { return 0 }
            return nil
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
                guard let current = item.weightKg,
                      let weight = target(item.exerciseId, reps: item.repRange.lower, accessory: item.role == .accessory) else { continue }
                weights[item.progressionKey] = weights[item.progressionKey] ?? weight
                guard weight != current else { continue }
                prescription.exercises[index].weightKg = weight
                changed = true
            }
            if changed {
                session.strengthPrescriptionData = StoredJSON.encode(prescription)
                session.touch(now: now)
            }
        }

        // Saved working weights (used for every week built from now on).
        let states = ((try? context.fetch(FetchDescriptor<ExerciseStateModel>())) ?? []).filter { !$0.isSoftDeleted }
        for state in states {
            let accessory = state.progressionKey.hasSuffix(".accessory")
            let reps = (accessory ? goal?.accessory.repsLow : goal?.main.repsLow) ?? state.repRangeLower
            guard let weight = weights[state.progressionKey] ?? target(state.exerciseId, reps: reps, accessory: accessory),
                  weight != state.workingWeightKg else { continue }
            state.workingWeightKg = weight
            state.stallCount = 0
            state.lastChangeReason = weight > 0 ? "Set from your lift numbers" : "Pick a weight on your first session"
            state.lastChangedAt = now
            state.touch(now: now)
        }

        // A plan workout they've opened but not finished: sets not done yet, unless they changed the weight.
        let open = ((try? context.fetch(FetchDescriptor<StrengthLogModel>())) ?? []).filter { !$0.isSoftDeleted && !$0.isFinished && !$0.isRecorded }
        for log in open {
            for set in log.sets where !set.isSoftDeleted && !set.isCompleted && !set.isBodyweight && set.actualWeightKg == set.targetWeightKg {
                let accessory = set.progressionKey.hasSuffix(".accessory")
                guard let weight = weights[set.progressionKey] ?? target(set.exerciseId, reps: set.repRangeLower, accessory: accessory),
                      weight != set.targetWeightKg else { continue }
                set.targetWeightKg = weight
                set.actualWeightKg = weight
                set.touch(now: now)
            }
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

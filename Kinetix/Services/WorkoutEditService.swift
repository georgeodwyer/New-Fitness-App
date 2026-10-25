import Foundation
import SwiftData
import TrainingEngine

/// Changes to a gym workout in progress: reordering exercises (when the kit isn't free in
/// the planned order) and swapping one for an alternative, optionally kept for next time.
@MainActor
enum WorkoutEditService {
    // MARK: Reorder

    /// Moves an exercise (all its sets) to just before another one, or to the end.
    static func move(key: String, before target: String?, in log: StrengthLogModel, context: ModelContext) {
        var order: [String] = []
        for set in log.orderedSets where !order.contains(set.progressionKey) {
            order.append(set.progressionKey)
        }
        guard let from = order.firstIndex(of: key), key != target else { return }
        order.remove(at: from)
        if let target, let to = order.firstIndex(of: target) {
            order.insert(key, at: to)
        } else {
            order.append(key)
        }
        for set in log.sets where !set.isSoftDeleted {
            if let index = order.firstIndex(of: set.progressionKey), set.exerciseOrder != index {
                set.exerciseOrder = index
                set.touch()
            }
        }
        log.touch()
        try? context.save()
    }

    // MARK: Swap

    /// Replaces an exercise's sets still to do with another exercise. Done sets stay as they
    /// were. Weights come from your working weight, then last time, then a sensible default.
    static func swap(key: String, to exercise: ExerciseDefinition, in log: StrengthLogModel, context: ModelContext) {
        let sets = log.orderedSets.filter { $0.progressionKey == key && !$0.isCompleted }
        guard let first = sets.first else { return }
        // Planned sessions track progress per exercise and role; recorded ones use a free key.
        let role = key.split(separator: ".").last.map(String.init) ?? "free"
        let newKey = role == "free" ? GymPrefill.freeKey(exerciseId: exercise.id) : "\(exercise.id).\(role)"
        let isBodyweight = exercise.loading == .bodyweight
        let weight = isBodyweight ? 0 : startingWeight(for: exercise, key: newKey, reps: first.repRangeLower, context: context)
        for set in sets {
            set.exerciseId = exercise.id
            set.exerciseName = exercise.name
            set.progressionKey = newKey
            set.isBodyweight = isBodyweight
            set.targetWeightKg = weight
            set.actualWeightKg = weight
            set.exerciseOrder = first.exerciseOrder
            set.touch()
        }
        log.touch()
        try? context.save()
    }

    private static func startingWeight(for exercise: ExerciseDefinition, key: String, reps: Int, context: ModelContext) -> Double {
        let descriptor = FetchDescriptor<ExerciseStateModel>(predicate: #Predicate { $0.progressionKey == key })
        if let state = (try? context.fetch(descriptor))?.first(where: { !$0.isSoftDeleted }) { return state.workingWeightKg }
        if let last = GymService.previousSets(exerciseId: exercise.id, in: context).first, last.weightKg > 0 { return last.weightKg }
        let profile = ((try? context.fetch(FetchDescriptor<UserProfileModel>())) ?? []).first { !$0.isSoftDeleted }?.profile
        // From their lift numbers for main lifts and linked variations (machines start at 0: "pick a weight").
        if let profile, let weight = StrengthMath.weight(for: exercise, estimates: profile.liftEstimates, reps: max(reps, 1),
                                                         accessory: key.hasSuffix(".accessory")) {
            return weight
        }
        return exercise.defaultWeight(for: profile?.liftingExperience ?? .beginner) ?? 0
    }

    // MARK: Keep the swap

    /// Where a swap can be kept: this day of the plan, or the saved workout it came from.
    enum KeepTarget: Equatable {
        case planDay(String)
        case savedWorkout(String)
    }

    static func keepTarget(for log: StrengthLogModel, exerciseId: String, context: ModelContext) -> KeepTarget? {
        if log.isRecorded {
            guard let id = log.templateId, let template = template(id, context: context) else { return nil }
            return .savedWorkout(template.name)
        }
        // Only exercises from the built-in library can go into a plan (your own exercises stay in your workouts).
        guard PlanService.templates.exercise(id: exerciseId) != nil, let planned = planned(for: log, context: context) else { return nil }
        return .planDay(planned.title)
    }

    /// Uses `to` instead of `from` from now on: in every future session of this plan day
    /// (and the weeks not built yet), or in the saved workout.
    static func keep(from fromId: String, to exercise: ExerciseDefinition, log: StrengthLogModel, context: ModelContext, now: Date = .now) {
        if log.isRecorded {
            guard let id = log.templateId, let template = template(id, context: context) else { return }
            template.items = template.items.map { item in
                guard item.exerciseId == fromId else { return item }
                var item = item
                item.exerciseId = exercise.id
                item.name = exercise.name
                item.isBodyweight = exercise.loading == .bodyweight
                return item
            }
            template.touch(now: now)
            try? context.save()
            SyncService.shared.requestSync()
            return
        }
        guard let planned = planned(for: log, context: context),
              let profileModel = ((try? context.fetch(FetchDescriptor<UserProfileModel>())) ?? []).first(where: { !$0.isSoftDeleted })
        else { return }
        let day = planned.title

        // The plan builder: a swap of a swap points straight at the latest choice.
        var profile = profileModel.profile
        var swaps = profile.exerciseSwaps ?? [:]
        var followedChain = false
        for (key, value) in swaps where value == fromId && key.hasPrefix(day + "|") {
            swaps[key] = exercise.id
            followedChain = true
        }
        if !followedChain { swaps[AthleteProfile.swapKey(day: day, exerciseId: fromId)] = exercise.id }
        // Swapping back to the plan's own exercise removes the swap.
        swaps = swaps.filter { $0.key != AthleteProfile.swapKey(day: day, exerciseId: $0.value) }
        profile.exerciseSwaps = swaps
        profileModel.profile = profile

        // Sessions already built for the coming weeks.
        let today = Calendar.kinetix.startOfDay(for: now)
        let sessions = ((try? context.fetch(FetchDescriptor<PlannedSessionModel>())) ?? []).filter {
            !$0.isSoftDeleted && $0.id != planned.id && $0.title == day && $0.date >= today
                && $0.status == .planned && ($0.plan?.isActive ?? true)
        }
        for session in sessions {
            guard var prescription = session.strengthPrescription,
                  prescription.exercises.contains(where: { $0.exerciseId == fromId }) else { continue }
            prescription.exercises = prescription.exercises.map { item in
                guard item.exerciseId == fromId else { return item }
                var item = item
                let key = "\(exercise.id).\(item.role.rawValue)"
                item.exerciseId = exercise.id
                item.name = exercise.name
                item.weightKg = exercise.loading == .bodyweight ? nil : startingWeight(for: exercise, key: key, reps: item.repRange.lower, context: context)
                return item
            }
            session.strengthPrescriptionData = StoredJSON.encode(prescription)
            session.touch(now: now)
        }
        try? context.save()
        SyncService.shared.requestSync()
    }

    private static func planned(for log: StrengthLogModel, context: ModelContext) -> PlannedSessionModel? {
        guard let id = log.plannedSessionId else { return nil }
        return try? context.fetch(FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.id == id })).first
    }

    private static func template(_ id: UUID, context: ModelContext) -> GymTemplateModel? {
        (try? context.fetch(FetchDescriptor<GymTemplateModel>(predicate: #Predicate { $0.id == id })))?.first { !$0.isSoftDeleted }
    }
}

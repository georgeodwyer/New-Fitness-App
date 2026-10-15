import Foundation
import SwiftData
import TrainingEngine

/// The gym tracker on the Record tab: the exercise library (built-in plus your own),
/// starting a workout pre-filled from last time, and adding exercises mid-workout.
/// Finishing goes through `StrengthService.finish` like a planned session.
@MainActor
enum GymService {
    /// Built-in exercises plus the ones you've added.
    static func library(in context: ModelContext) -> [ExerciseDefinition] {
        let custom = ((try? context.fetch(FetchDescriptor<CustomExerciseModel>())) ?? [])
            .filter { !$0.isSoftDeleted }
            .map(\.definition)
        return PlanService.templates.exercises + custom
    }

    /// Sets from the most recent finished workout that included this exercise (planned or recorded).
    static func previousSets(exerciseId: String, excluding log: StrengthLogModel? = nil, in context: ModelContext) -> [PreviousSet] {
        let descriptor = FetchDescriptor<SetLogModel>(predicate: #Predicate { $0.exerciseId == exerciseId && $0.completedAt != nil })
        let sets = ((try? context.fetch(descriptor)) ?? []).filter { set in
            guard let session = set.session else { return false }
            return !set.isSoftDeleted && !session.isSoftDeleted && session.isFinished && session.id != log?.id
        }
        guard let latest = sets.compactMap(\.session).max(by: { $0.startedAt < $1.startedAt }) else { return [] }
        return sets
            .filter { $0.session?.id == latest.id }
            .sorted { $0.setIndex < $1.setIndex }
            .map { PreviousSet(weightKg: $0.isBodyweight ? 0 : $0.actualWeightKg, reps: $0.actualReps) }
    }

    /// "Last time: 3 × 8 @ 60 kg" for an exercise, if you've done it before.
    static func lastTimeText(exerciseId: String, isBodyweight: Bool, units: UnitSystem, excluding log: StrengthLogModel?,
                             in context: ModelContext) -> String? {
        let format = DisplayFormat(units: units)
        return GymPrefill.lastTimeText(previousSets(exerciseId: exerciseId, excluding: log, in: context),
                                       isBodyweight: isBodyweight, formatWeight: { format.weight($0) })
    }

    /// An unfinished workout started from the Record tab, to offer resuming it.
    static func inProgress(in context: ModelContext) -> StrengthLogModel? {
        let descriptor = FetchDescriptor<StrengthLogModel>(predicate: #Predicate { $0.isRecorded && !$0.isFinished },
                                                           sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).first { !$0.isSoftDeleted }
    }

    /// Creates a recorded workout with every exercise pre-filled from last time.
    static func start(title: String, items: [GymTemplateItem], linkedPlanned: PlannedSessionModel?,
                      in context: ModelContext, now: Date = .now) -> StrengthLogModel {
        let log = StrengthLogModel(plannedSessionId: linkedPlanned?.id, startedAt: now)
        log.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Gym workout" : title
        log.isRecorded = true
        context.insert(log)
        var seen = Set<String>()
        for item in items where seen.insert(item.exerciseId).inserted {
            insertSets(for: item, order: seen.count - 1, into: log, in: context, now: now)
        }
        try? context.save()
        return log
    }

    /// Adds an exercise to the end of a workout in progress (ignored if it's already there).
    static func addExercise(_ item: GymTemplateItem, to log: StrengthLogModel, in context: ModelContext, now: Date = .now) {
        let sets = log.orderedSets
        guard !sets.contains(where: { $0.exerciseId == item.exerciseId }) else { return }
        let order = (sets.map(\.exerciseOrder).max() ?? -1) + 1
        insertSets(for: item, order: order, into: log, in: context, now: now)
        log.touch(now: now)
        try? context.save()
    }

    /// Removes an exercise (all its sets) from a workout in progress.
    static func removeExercise(key: String, from log: StrengthLogModel, in context: ModelContext) {
        for set in log.sets where set.progressionKey == key {
            set.softDelete()
        }
        log.touch()
        try? context.save()
    }

    /// The exercises in a workout, as template items (for "Save as template").
    static func items(from log: StrengthLogModel) -> [GymTemplateItem] {
        var result: [GymTemplateItem] = []
        for set in log.orderedSets {
            if let index = result.lastIndex(where: { $0.exerciseId == set.exerciseId }) {
                result[index].sets += 1
            } else {
                result.append(GymTemplateItem(exerciseId: set.exerciseId, name: set.exerciseName, sets: 1,
                                              repsLow: set.repRangeLower, repsHigh: set.repRangeUpper,
                                              restSeconds: set.restSeconds, isBodyweight: set.isBodyweight))
            }
        }
        return result
    }

    private static func insertSets(for item: GymTemplateItem, order: Int, into log: StrengthLogModel, in context: ModelContext, now: Date) {
        let definition = library(in: context).first { $0.id == item.exerciseId }
        let level = ((try? context.fetch(FetchDescriptor<UserProfileModel>())) ?? []).first { !$0.isSoftDeleted }?.profile.liftingExperience
        let defaultWeight = definition?.defaultWeight(for: level ?? .beginner)
        let previous = previousSets(exerciseId: item.exerciseId, excluding: log, in: context)
        let prefilled = GymPrefill.sets(for: item, previous: previous, defaultWeightKg: defaultWeight)
        for (index, values) in prefilled.enumerated() {
            let set = SetLogModel(exerciseId: item.exerciseId, setIndex: index, targetReps: values.reps, targetWeightKg: values.weightKg, now: now)
            set.progressionKey = GymPrefill.freeKey(exerciseId: item.exerciseId)
            set.exerciseName = item.name
            set.exerciseOrder = order
            set.repRangeLower = item.repsLow
            set.repRangeUpper = item.repsHigh
            set.restSeconds = item.restSeconds
            set.isBodyweight = item.isBodyweight
            context.insert(set)
            set.session = log
        }
    }
}

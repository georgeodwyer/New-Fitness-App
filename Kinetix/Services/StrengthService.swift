import Foundation
import SwiftData
import TrainingEngine

/// Runs the strength side of the app: starting/resuming a workout, and on finish
/// applying double progression, recording PRs, and updating future sessions.
@MainActor
enum StrengthService {
    struct ExerciseChange: Identifiable {
        let id = UUID()
        let exerciseName: String
        let change: ProgressionDecision.Change
        let reason: String
    }

    struct RecordAchieved: Identifiable {
        let id = UUID()
        let exerciseName: String
        let record: PersonalRecord
    }

    struct Summary {
        var title: String
        var durationSeconds: Double
        var volumeKg: Double
        var completedSets: Int
        var effort: Double
        var load: Double
        var changes: [ExerciseChange]
        var records: [RecordAchieved]
    }

    /// Returns the in-progress log for this session, or creates one pre-filled with targets.
    static func startOrResume(_ session: PlannedSessionModel, in context: ModelContext, now: Date = .now) -> StrengthLogModel {
        let sessionID: UUID? = session.id
        let descriptor = FetchDescriptor<StrengthLogModel>(predicate: #Predicate { $0.plannedSessionId == sessionID && !$0.isFinished })
        if let existing = try? context.fetch(descriptor).first(where: { !$0.isSoftDeleted }) {
            return existing
        }

        let log = StrengthLogModel(plannedSessionId: session.id, startedAt: now)
        log.title = session.title
        context.insert(log)
        let weights = PlanService.workingWeights(in: context)
        let prescription = session.strengthPrescription?.exercises ?? []
        for (order, exercise) in prescription.enumerated() {
            // Use the latest working weight (progression may have moved on since the plan was generated).
            let weight = exercise.weightKg.map { weights[exercise.progressionKey] ?? $0 } ?? 0
            for index in 0..<exercise.sets {
                let set = SetLogModel(exerciseId: exercise.exerciseId, setIndex: index, targetReps: exercise.repRange.upper, targetWeightKg: weight, now: now)
                set.progressionKey = exercise.progressionKey
                set.exerciseName = exercise.name
                set.exerciseOrder = order
                set.repRangeLower = exercise.repRange.lower
                set.repRangeUpper = exercise.repRange.upper
                set.restSeconds = exercise.restSeconds
                set.isBodyweight = exercise.weightKg == nil
                context.insert(set)
                set.session = log
            }
        }
        try? context.save()
        return log
    }

    /// Adds one more set to an exercise, copying the previous set's targets.
    static func addSet(after last: SetLogModel, to log: StrengthLogModel, in context: ModelContext) {
        let set = SetLogModel(exerciseId: last.exerciseId, setIndex: last.setIndex + 1, targetReps: last.targetReps, targetWeightKg: last.actualWeightKg)
        set.progressionKey = last.progressionKey
        set.exerciseName = last.exerciseName
        set.exerciseOrder = last.exerciseOrder
        set.repRangeLower = last.repRangeLower
        set.repRangeUpper = last.repRangeUpper
        set.restSeconds = last.restSeconds
        set.isBodyweight = last.isBodyweight
        context.insert(set)
        set.session = log
        log.touch()
    }

    /// Completes the workout: progression, records, load, and plan updates.
    static func finish(
        _ log: StrengthLogModel,
        planned: PlannedSessionModel?,
        effort: Double,
        units: UnitSystem,
        in context: ModelContext,
        now: Date = .now
    ) -> Summary {
        let templates = PlanService.templates
        let rules = templates.strength.progressionRules
        let sets = log.orderedSets
        let groups = Dictionary(grouping: sets, by: \.progressionKey)
        let orderedKeys = groups.keys.sorted { (groups[$0]?.first?.exerciseOrder ?? 0) < (groups[$1]?.first?.exerciseOrder ?? 0) }

        var changes: [ExerciseChange] = []
        var records: [RecordAchieved] = []
        var newWeights: [String: Double] = [:]

        for key in orderedKeys {
            guard let exerciseSets = groups[key], let first = exerciseSets.first else { continue }
            let results = exerciseSets.map {
                SetResult(weightKg: $0.isBodyweight ? nil : $0.actualWeightKg, reps: $0.actualReps, rpe: $0.rpe, completed: $0.isCompleted)
            }
            let definition = templates.exercise(id: first.exerciseId)
            let range = RepRange(first.repRangeLower, first.repRangeUpper)

            // Progression.
            let stateModel = exerciseState(for: key, first: first, in: context)
            let state = ProgressionState(workingWeightKg: stateModel?.workingWeightKg ?? first.targetWeightKg,
                                         stallCount: stateModel?.stallCount ?? 0)
            let decision = Progression.evaluate(
                exerciseName: first.exerciseName,
                loading: definition?.loading ?? (first.isBodyweight ? .bodyweight : .barbell),
                region: definition?.region ?? .upper,
                repRange: range,
                prescribedSets: exerciseSets.count,
                state: state,
                sets: results,
                rules: rules,
                units: units
            )
            if decision.change != .none, let stateModel {
                stateModel.workingWeightKg = decision.newState.workingWeightKg
                stateModel.stallCount = decision.newState.stallCount
                stateModel.lastChangeReason = decision.reason
                stateModel.lastChangedAt = now
                stateModel.touch(now: now)
                newWeights[key] = decision.newState.workingWeightKg
            }
            if results.contains(where: \.completed) {
                changes.append(ExerciseChange(exerciseName: first.exerciseName, change: decision.change, reason: decision.reason))
            }

            // Personal records (per exercise, across roles).
            let previous = storedBests(for: first.exerciseId, in: context)
            let beaten = PersonalRecords.newRecords(sets: results, previousBests: previous.mapValues(\.value))
            records += beaten.map { RecordAchieved(exerciseName: first.exerciseName, record: $0) }
            for (kind, value) in PersonalRecords.bests(in: results) {
                if let existing = previous[kind] {
                    if value > existing.value {
                        existing.value = value
                        existing.achievedAt = now
                        existing.touch(now: now)
                    }
                } else {
                    context.insert(PersonalRecordModel(recordKey: first.exerciseId, kindRaw: kind.rawValue, value: value, achievedAt: now))
                }
            }
        }

        // Session totals and load (sRPE = minutes × effort).
        let duration = min(now.timeIntervalSince(log.startedAt), 4 * 3600)
        let completed = sets.filter(\.isCompleted)
        log.durationSeconds = duration
        log.effort = effort
        log.load = SessionLoad.srpe(durationSeconds: duration, effort: effort)
        log.isFinished = true
        log.finishedAt = now
        log.touch(now: now)

        if let planned {
            planned.status = .completed
        }
        applyNewWeights(newWeights, in: context, now: now)
        try? context.save()

        return Summary(
            title: log.title,
            durationSeconds: duration,
            volumeKg: log.volumeKg,
            completedSets: completed.count,
            effort: effort,
            load: log.load,
            changes: changes,
            records: records
        )
    }

    /// Abandons an in-progress workout (its sets are removed).
    static func discard(_ log: StrengthLogModel, in context: ModelContext) {
        context.delete(log)
        try? context.save()
    }

    // MARK: - Helpers

    private static func exerciseState(for key: String, first: SetLogModel, in context: ModelContext) -> ExerciseStateModel? {
        let descriptor = FetchDescriptor<ExerciseStateModel>(predicate: #Predicate { $0.progressionKey == key })
        if let existing = try? context.fetch(descriptor).first { return existing }
        guard !first.isBodyweight else { return nil }
        let state = ExerciseStateModel(progressionKey: key, exerciseId: first.exerciseId, workingWeightKg: first.targetWeightKg,
                                       repRangeLower: first.repRangeLower, repRangeUpper: first.repRangeUpper)
        state.exerciseName = first.exerciseName
        context.insert(state)
        return state
    }

    private static func storedBests(for exerciseId: String, in context: ModelContext) -> [RecordKind: PersonalRecordModel] {
        let descriptor = FetchDescriptor<PersonalRecordModel>(predicate: #Predicate { $0.recordKey == exerciseId })
        let models = (try? context.fetch(descriptor)) ?? []
        var result: [RecordKind: PersonalRecordModel] = [:]
        for model in models where !model.isSoftDeleted {
            if let kind = RecordKind(rawValue: model.kindRaw) { result[kind] = model }
        }
        return result
    }

    /// Updates the weights in already-generated future sessions.
    private static func applyNewWeights(_ weights: [String: Double], in context: ModelContext, now: Date) {
        guard !weights.isEmpty else { return }
        let planned = SessionStatus.planned.rawValue
        let today = Calendar.kinetix.startOfDay(for: now)
        let descriptor = FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.statusRaw == planned && $0.date >= today })
        for session in (try? context.fetch(descriptor)) ?? [] {
            guard var prescription = session.strengthPrescription else { continue }
            var changed = false
            for index in prescription.exercises.indices {
                let key = prescription.exercises[index].progressionKey
                if let weight = weights[key], prescription.exercises[index].weightKg != nil {
                    prescription.exercises[index].weightKg = weight
                    changed = true
                }
            }
            if changed {
                session.strengthPrescriptionData = StoredJSON.encode(prescription)
                session.touch(now: now)
            }
        }
    }
}

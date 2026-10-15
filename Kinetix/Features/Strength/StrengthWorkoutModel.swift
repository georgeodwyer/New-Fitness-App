import Foundation
import Observation
import SwiftData
import TrainingEngine

/// Live state of a strength workout: grouped sets and the rest timer.
@Observable
@MainActor
final class StrengthWorkoutModel {
    struct ExerciseGroup: Identifiable {
        let key: String
        let name: String
        let sets: [SetLogModel]
        var id: String { key }
        var first: SetLogModel { sets[0] }
        var isComplete: Bool { sets.allSatisfy(\.isCompleted) }
    }

    let log: StrengthLogModel
    let planned: PlannedSessionModel?
    private let context: ModelContext

    /// When the current rest ends (nil = not resting).
    private(set) var restEndsAt: Date?
    private(set) var restTotalSeconds: Double = 0
    /// Increments when a rest finishes (drives haptics).
    private(set) var restFinishedCount = 0
    private var restTask: Task<Void, Never>?

    init(log: StrengthLogModel, planned: PlannedSessionModel?, context: ModelContext, units: UnitSystem = .metric) {
        self.log = log
        self.planned = planned
        self.context = context
        self.units = units
        refreshLastTime()
        WorkoutActivityController.shared.start(title: log.title.isEmpty ? "Strength" : log.title, kind: "strength",
                                               state: lockScreenState)
    }

    private let units: UnitSystem

    // MARK: Lock screen

    /// The next set to do, e.g. "Back Squat · set 3 of 5 · 100 kg × 5".
    private var nextSetText: String? {
        guard let group = groups.first(where: { !$0.isComplete }),
              let set = group.sets.first(where: { !$0.isCompleted }),
              let index = group.sets.firstIndex(where: { $0.id == set.id }) else { return nil }
        let load = set.isBodyweight ? "\(set.actualReps) reps"
            : "\(DisplayFormat(units: units).weight(set.actualWeightKg)) × \(set.actualReps)"
        return "\(group.name) · set \(index + 1) of \(group.sets.count) · \(load)"
    }

    private var lockScreenState: WorkoutActivityAttributes.ContentState {
        let resting = restEndsAt.map { $0 > .now } ?? false
        return WorkoutActivityAttributes.ContentState(
            mode: resting ? .resting : .lifting,
            timerStart: log.startedAt,
            elapsedSeconds: Date.now.timeIntervalSince(log.startedAt),
            restEndsAt: resting ? restEndsAt : nil,
            setsDone: completedSets,
            setsTotal: totalSets,
            nextSet: nextSetText
        )
    }

    private func updateLockScreen() {
        WorkoutActivityController.shared.update(lockScreenState, important: true)
    }

    /// Call when leaving the workout (finished, discarded or closed).
    func endLockScreen() {
        WorkoutActivityController.shared.end()
    }

    var groups: [ExerciseGroup] {
        let sets = log.orderedSets
        var result: [ExerciseGroup] = []
        for set in sets {
            if let last = result.last, last.key == set.progressionKey {
                result[result.count - 1] = ExerciseGroup(key: last.key, name: last.name, sets: last.sets + [set])
            } else {
                result.append(ExerciseGroup(key: set.progressionKey, name: set.exerciseName, sets: [set]))
            }
        }
        return result
    }

    /// The first exercise with sets still to do.
    var currentKey: String? { groups.first { !$0.isComplete }?.key }

    var completedSets: Int { log.orderedSets.filter(\.isCompleted).count }
    var totalSets: Int { log.orderedSets.count }

    func toggleComplete(_ set: SetLogModel) {
        if set.isCompleted {
            set.completedAt = nil
        } else {
            set.completedAt = .now
            startRest(seconds: Double(set.restSeconds))
        }
        set.touch()
        save()
        updateLockScreen()
    }

    func setRPE(_ value: Double?, for set: SetLogModel) {
        set.rpe = value
        set.touch()
        save()
    }

    func update(_ set: SetLogModel, weight: Double? = nil, reps: Int? = nil) {
        if let weight { set.actualWeightKg = max(0, weight) }
        if let reps { set.actualReps = max(0, reps) }
        set.touch()
        save()
    }

    // MARK: Your own workouts

    /// "Last time: 3 × 8 @ 60 kg" per exercise id.
    private(set) var lastTime: [String: String] = [:]
    /// Set after "Save as template" so the screen can confirm it.
    private(set) var savedTemplateName: String?

    /// Exercises can be added to, or removed from, workouts started on the Record tab.
    var canEditExercises: Bool { log.isRecorded }

    var exerciseIds: Set<String> { Set(log.orderedSets.map(\.exerciseId)) }

    private func refreshLastTime() {
        var result: [String: String] = [:]
        for group in groups {
            let first = group.first
            if let text = GymService.lastTimeText(exerciseId: first.exerciseId, isBodyweight: first.isBodyweight,
                                                  units: units, excluding: log, in: context) {
                result[first.exerciseId] = text
            }
        }
        lastTime = result
    }

    func addExercise(_ exercise: ExerciseDefinition) {
        GymService.addExercise(GymTemplateItem.starter(for: exercise), to: log, in: context)
        refreshLastTime()
        updateLockScreen()
    }

    func removeExercise(_ group: ExerciseGroup) {
        GymService.removeExercise(key: group.key, from: log, in: context)
        updateLockScreen()
    }

    func saveAsTemplate() {
        let items = GymService.items(from: log)
        guard !items.isEmpty else { return }
        let template = GymTemplateModel(name: log.title, items: items)
        template.lastUsedAt = .now
        context.insert(template)
        save()
        SyncService.shared.requestSync()
        savedTemplateName = log.title
    }

    func addSet(to group: ExerciseGroup) {
        guard let last = group.sets.last else { return }
        StrengthService.addSet(after: last, to: log, in: context)
        save()
    }

    // MARK: Rest timer

    func startRest(seconds: Double) {
        guard seconds > 0 else { return }
        restTotalSeconds = seconds
        restEndsAt = Date.now.addingTimeInterval(seconds)
        scheduleRestEnd()
        updateLockScreen()
    }

    func extendRest(by seconds: Double) {
        guard let end = restEndsAt else { return }
        restEndsAt = end.addingTimeInterval(seconds)
        restTotalSeconds += seconds
        scheduleRestEnd()
        updateLockScreen()
    }

    func skipRest() {
        restTask?.cancel()
        restEndsAt = nil
        updateLockScreen()
    }

    private func scheduleRestEnd() {
        restTask?.cancel()
        guard let end = restEndsAt else { return }
        restTask = Task { [weak self] in
            let delay = end.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            self?.restEndsAt = nil
            self?.restFinishedCount += 1
            self?.updateLockScreen()
        }
    }

    private func save() {
        try? context.save()
    }
}

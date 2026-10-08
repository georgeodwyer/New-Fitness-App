import Foundation
import Observation
import SwiftData

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

    init(log: StrengthLogModel, planned: PlannedSessionModel?, context: ModelContext) {
        self.log = log
        self.planned = planned
        self.context = context
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

    var completedSets: Int { log.sets.filter(\.isCompleted).count }
    var totalSets: Int { log.sets.count }

    func toggleComplete(_ set: SetLogModel) {
        if set.isCompleted {
            set.completedAt = nil
        } else {
            set.completedAt = .now
            startRest(seconds: Double(set.restSeconds))
        }
        set.touch()
        save()
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
    }

    func extendRest(by seconds: Double) {
        guard let end = restEndsAt else { return }
        restEndsAt = end.addingTimeInterval(seconds)
        restTotalSeconds += seconds
        scheduleRestEnd()
    }

    func skipRest() {
        restTask?.cancel()
        restEndsAt = nil
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
        }
    }

    private func save() {
        try? context.save()
    }
}

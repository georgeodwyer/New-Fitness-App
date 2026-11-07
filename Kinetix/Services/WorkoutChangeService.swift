import Foundation
import SwiftData
import TrainingEngine

/// One change made to a gym workout while doing it, that can be kept for next time.
struct WorkoutChange: Identifiable, Equatable {
    enum Kind: Equatable {
        case added(GymTemplateItem)
        case sets(exerciseId: String, name: String, from: Int, to: Int)
        case removed(exerciseId: String, name: String)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .added(let item): return "added-\(item.exerciseId)"
        case .sets(let id, _, _, _): return "sets-\(id)"
        case .removed(let id, _): return "removed-\(id)"
        }
    }

    /// "Added Dumbbell Curl (3 sets)", "Bench Press: 4 sets instead of 3", "Dropped Dips".
    var text: String {
        switch kind {
        case .added(let item): return "Added \(item.name) (\(item.sets) set\(item.sets == 1 ? "" : "s"))"
        case .sets(_, let name, let from, let to): return "\(name): \(to) set\(to == 1 ? "" : "s") instead of \(from)"
        case .removed(_, let name): return "Dropped \(name)"
        }
    }
}

/// Spots what changed in a gym workout (exercises added or dropped, sets added or removed)
/// and, when they say so, keeps it: in the saved workout, their own Gym day, or the plan's day.
@MainActor
enum WorkoutChangeService {
    /// The workout as it started: sets per exercise, and names.
    struct Baseline: Equatable {
        var sets: [String: Int]
        var names: [String: String]
    }

    static func baseline(_ log: StrengthLogModel) -> Baseline {
        var sets: [String: Int] = [:]
        var names: [String: String] = [:]
        for set in log.orderedSets {
            sets[set.exerciseId, default: 0] += 1
            names[set.exerciseId] = set.exerciseName
        }
        return Baseline(sets: sets, names: names)
    }

    /// Changes since the start. Swapped exercises are left out (a swap asks there and then).
    static func changes(since baseline: Baseline, log: StrengthLogModel, swapped: Set<String>) -> [WorkoutChange] {
        let items = GymService.items(from: log)
        var result: [WorkoutChange] = []
        for item in items where !swapped.contains(item.exerciseId) {
            if let before = baseline.sets[item.exerciseId] {
                if before != item.sets {
                    result.append(WorkoutChange(kind: .sets(exerciseId: item.exerciseId, name: item.name, from: before, to: item.sets)))
                }
            } else {
                result.append(WorkoutChange(kind: .added(item)))
            }
        }
        let now = Set(items.map(\.exerciseId))
        for (id, _) in baseline.sets where !now.contains(id) && !swapped.contains(id) {
            result.append(WorkoutChange(kind: .removed(exerciseId: id, name: baseline.names[id] ?? id)))
        }
        return result
    }

    /// Where changes would be kept, in words ("your Push sessions", "“Leg day”"); nil when
    /// there's nowhere (an empty workout started from scratch).
    static func targetName(for log: StrengthLogModel, context: ModelContext) -> String? {
        if log.isRecorded {
            guard let id = log.templateId, let template = template(id, context: context) else { return nil }
            return "\u{201C}\(template.name)\u{201D}"
        }
        guard let planned = planned(for: log, context: context) else { return nil }
        return "your \(planned.title) sessions"
    }

    static func keep(_ changes: [WorkoutChange], log: StrengthLogModel, context: ModelContext, now: Date = .now) {
        guard !changes.isEmpty else { return }
        // A saved workout from the Workout tab.
        if log.isRecorded {
            guard let id = log.templateId, let template = template(id, context: context) else { return }
            template.items = apply(changes, to: template.items)
            template.touch(now: now)
            try? context.save()
            SyncService.shared.requestSync()
            return
        }
        guard let planned = planned(for: log, context: context),
              let profileModel = ((try? context.fetch(FetchDescriptor<UserProfileModel>())) ?? []).first(where: { !$0.isSoftDeleted })
        else { return }
        var profile = profileModel.profile
        if let slot = planned.gymSlotNumber, var own = profile.ownGymWorkouts?[slot] {
            // Their own workout on a Gym n day.
            own.exercises = apply(changes, to: own.exercises)
            profile.ownGymWorkouts?[slot] = own
        } else {
            // A plan day: remembered by the day's name and used every week.
            var dayChange = profile.planDayChanges?[planned.title] ?? PlanDayChange()
            for change in changes {
                switch change.kind {
                case .added(let item):
                    dayChange.removed.removeAll { $0 == item.exerciseId }
                    if !dayChange.added.contains(where: { $0.exerciseId == item.exerciseId }) { dayChange.added.append(item) }
                case .sets(let id, _, _, let to):
                    if let index = dayChange.added.firstIndex(where: { $0.exerciseId == id }) {
                        dayChange.added[index].sets = to
                    } else {
                        dayChange.sets[id] = to
                    }
                case .removed(let id, _):
                    if dayChange.added.contains(where: { $0.exerciseId == id }) {
                        dayChange.added.removeAll { $0.exerciseId == id }
                    } else if !dayChange.removed.contains(id) {
                        dayChange.removed.append(id)
                    }
                    dayChange.sets[id] = nil
                }
            }
            var all = profile.planDayChanges ?? [:]
            all[planned.title] = dayChange.isEmpty ? nil : dayChange
            profile.planDayChanges = all.isEmpty ? nil : all
        }
        profileModel.profile = profile

        // Sessions already built for the coming weeks.
        let today = Calendar.kinetix.startOfDay(for: now)
        let title = planned.title
        let sessions = ((try? context.fetch(FetchDescriptor<PlannedSessionModel>())) ?? []).filter {
            !$0.isSoftDeleted && $0.id != planned.id && $0.title == title && $0.date >= today
                && $0.status == .planned && ($0.plan?.isActive ?? true)
        }
        for session in sessions {
            guard var prescription = session.strengthPrescription else { continue }
            prescription.exercises = apply(changes, to: prescription.exercises, log: log)
            session.strengthPrescriptionData = StoredJSON.encode(prescription)
            session.touch(now: now)
        }
        try? context.save()
        SyncService.shared.requestSync()
    }

    // MARK: Applying

    static func apply(_ changes: [WorkoutChange], to items: [GymTemplateItem]) -> [GymTemplateItem] {
        var items = items
        for change in changes {
            switch change.kind {
            case .added(let item):
                if !items.contains(where: { $0.exerciseId == item.exerciseId }) { items.append(item) }
            case .sets(let id, _, _, let to):
                for index in items.indices where items[index].exerciseId == id { items[index].sets = to }
            case .removed(let id, _):
                items.removeAll { $0.exerciseId == id }
            }
        }
        return items
    }

    private static func apply(_ changes: [WorkoutChange], to exercises: [ExercisePrescription],
                              log: StrengthLogModel) -> [ExercisePrescription] {
        var exercises = exercises
        for change in changes {
            switch change.kind {
            case .added(let item):
                guard !exercises.contains(where: { $0.exerciseId == item.exerciseId }) else { continue }
                // The weight they used today.
                let weight = log.orderedSets.last { $0.exerciseId == item.exerciseId && $0.isCompleted }?.actualWeightKg ?? 0
                exercises.append(ExercisePrescription(exerciseId: item.exerciseId, name: item.name, role: .accessory, sets: item.sets,
                                                      repRange: RepRange(item.repsLow, item.repsHigh),
                                                      weightKg: item.isBodyweight ? nil : weight, restSeconds: item.restSeconds))
            case .sets(let id, _, _, let to):
                for index in exercises.indices where exercises[index].exerciseId == id { exercises[index].sets = to }
            case .removed(let id, _):
                exercises.removeAll { $0.exerciseId == id }
            }
        }
        return exercises
    }

    private static func planned(for log: StrengthLogModel, context: ModelContext) -> PlannedSessionModel? {
        guard let id = log.plannedSessionId else { return nil }
        return try? context.fetch(FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.id == id })).first
    }

    private static func template(_ id: UUID, context: ModelContext) -> GymTemplateModel? {
        (try? context.fetch(FetchDescriptor<GymTemplateModel>(predicate: #Predicate { $0.id == id })))?.first { !$0.isSoftDeleted }
    }
}

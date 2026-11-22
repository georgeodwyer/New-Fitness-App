import Foundation
import SwiftData
import TrainingEngine

/// Finished sessions and planned ones, as achievements, points and statistics see them: runs,
/// gym and functional sessions in Kinetix, plus runs and workouts from other apps (Apple Health)
/// that Kinetix didn't record. Every session counts fully.
enum ActivityRecords {
    static func make(runs: [RunLogModel], lifts: [StrengthLogModel], external: [ExternalWorkout] = []) -> [ActivityRecord] {
        let countedRuns = runs.filter { $0.isFinished && !$0.isSoftDeleted && !$0.usedSimulatedGPS }
        let finishedLifts = lifts.filter { $0.isFinished && !$0.isSoftDeleted }
        var records = countedRuns.map { run in
            ActivityRecord(id: run.id, start: run.startedAt, durationSeconds: run.durationSeconds, kind: .run, load: run.load,
                           distanceMeters: run.distanceMeters, runType: run.runTypeRaw,
                           splitSeconds: run.splits.map(\.durationSeconds),
                           cadence: RunCadence.averageCadence(run.stepSamples, durationSeconds: run.durationSeconds))
        }
        records += finishedLifts.map { lift in
            ActivityRecord(id: lift.id, start: lift.startedAt, durationSeconds: lift.durationSeconds,
                           kind: lift.isFunctional ? .functional : .gym, load: lift.load,
                           distanceMeters: lift.functionalRunMeters,
                           sets: lift.sets.filter { $0.isCompleted && !$0.isSoftDeleted }.count)
        }
        // Other apps' workouts that Kinetix didn't record (so nothing is counted twice).
        let recorded = records.map { DateInterval(start: $0.start, duration: max($0.durationSeconds, 60)) }
        for workout in ExternalWorkouts.notRecorded(external, excluding: recorded) {
            let kind: ActivityRecord.Kind
            switch workout.kind {
            case .run: kind = .run
            case .strength: kind = .gym
            default: kind = .other
            }
            records.append(ActivityRecord(id: workout.id, start: workout.start, durationSeconds: workout.durationSeconds, kind: kind,
                                          load: workout.estimatedEffort(maxHeartRate: nil) * workout.durationSeconds / 60,
                                          distanceMeters: workout.distanceMeters ?? 0))
        }
        return records.sorted { $0.start > $1.start }
    }

    static func planned(_ sessions: [PlannedSessionModel], now: Date = .now) -> [PlannedRecord] {
        sessions.filter { !$0.isSoftDeleted && $0.date <= now && ($0.kind.discipline == .run || $0.kind.discipline == .strength) }
            .map { PlannedRecord(date: $0.date, completed: $0.status == .completed) }
    }

    static func recordDates(_ records: [PersonalRecordModel]) -> [Date] {
        records.filter { !$0.isSoftDeleted }.map(\.achievedAt)
    }

    /// Everything from the store at once (for screens that need the whole picture).
    @MainActor
    static func all(in context: ModelContext, now: Date = .now) -> (activities: [ActivityRecord], planned: [PlannedRecord]) {
        func fetch<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        let activities = make(runs: fetch(RunLogModel.self), lifts: fetch(StrengthLogModel.self),
                              external: IntegrationSettings.shared.loadWorkouts)
        let planned = planned(fetch(PlannedSessionModel.self).filter { $0.plan?.isActive ?? true }, now: now)
        return (activities, planned)
    }
}

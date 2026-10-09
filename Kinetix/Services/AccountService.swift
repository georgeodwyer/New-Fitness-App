import Foundation
import SwiftData
import TrainingEngine

/// Data export and deletion (export is your right under GDPR; in-app deletion is
/// required by the App Store once accounts exist).
@MainActor
enum AccountService {
    // MARK: Export

    struct Export: Encodable {
        struct Session: Encodable {
            var date: Date
            var slot: String
            var title: String
            var summary: String
            var kind: SessionKind
            var status: String
            var isKey: Bool
            var plannedMinutes: Double
            var plannedEffort: Double
            var changeReason: String?
            var runStructure: RunStructure?
            var strength: StrengthPrescription?
        }
        struct Run: Encodable {
            var title: String
            var startedAt: Date
            var durationSeconds: Double
            var distanceMeters: Double
            var effort: Double
            var load: Double
            var averageHeartRate: Double?
            var timeInTargetSeconds: Double
            var splits: [Split]
            var route: [RoutePoint]
        }
        struct LoggedSet: Encodable {
            var exercise: String
            var setNumber: Int
            var weightKg: Double?
            var reps: Int
            var rpe: Double?
        }
        struct Workout: Encodable {
            var title: String
            var startedAt: Date
            var durationSeconds: Double
            var effort: Double
            var load: Double
            var volumeKg: Double
            var sets: [LoggedSet]
        }
        struct Record: Encodable {
            var exerciseId: String
            var kind: String
            var value: Double
            var achievedAt: Date
        }
        struct CheckIn: Encodable {
            var date: Date
            var sleep: Int
            var soreness: Int
            var energy: Int
        }
        struct Change: Encodable {
            var date: Date
            var summary: String
        }

        var exportedAt: Date
        var app = "Kinetix"
        var profile: AthleteProfile?
        var plannedSessions: [Session]
        var runs: [Run]
        var strengthWorkouts: [Workout]
        var personalRecords: [Record]
        var checkIns: [CheckIn]
        var planChanges: [Change]
    }

    static func makeExport(in context: ModelContext, now: Date = .now) -> Export {
        func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        let sessions = all(PlannedSessionModel.self).filter { !$0.isSoftDeleted }.sorted { $0.date < $1.date }
        let runs = all(RunLogModel.self).filter { $0.isFinished && !$0.isSoftDeleted }.sorted { $0.startedAt < $1.startedAt }
        let workouts = all(StrengthLogModel.self).filter { $0.isFinished && !$0.isSoftDeleted }.sorted { $0.startedAt < $1.startedAt }
        return Export(
            exportedAt: now,
            profile: all(UserProfileModel.self).first { !$0.isSoftDeleted }?.profile,
            plannedSessions: sessions.map {
                Export.Session(date: $0.date, slot: $0.slot.rawValue, title: $0.title, summary: $0.summary, kind: $0.kind,
                               status: $0.status.rawValue, isKey: $0.isKey, plannedMinutes: $0.plannedDurationMinutes,
                               plannedEffort: $0.plannedEffort, changeReason: $0.changeReason,
                               runStructure: $0.runStructure, strength: $0.strengthPrescription)
            },
            runs: runs.map {
                Export.Run(title: $0.title, startedAt: $0.startedAt, durationSeconds: $0.durationSeconds, distanceMeters: $0.distanceMeters,
                           effort: $0.effort, load: $0.load, averageHeartRate: $0.averageHeartRate,
                           timeInTargetSeconds: $0.timeInTargetSeconds, splits: $0.splits, route: $0.route)
            },
            strengthWorkouts: workouts.map { workout in
                Export.Workout(title: workout.title, startedAt: workout.startedAt, durationSeconds: workout.durationSeconds,
                               effort: workout.effort, load: workout.load, volumeKg: workout.volumeKg,
                               sets: workout.orderedSets.filter(\.isCompleted).map {
                                   Export.LoggedSet(exercise: $0.exerciseName, setNumber: $0.setIndex + 1,
                                                    weightKg: $0.isBodyweight ? nil : $0.actualWeightKg, reps: $0.actualReps, rpe: $0.rpe)
                               })
            },
            personalRecords: all(PersonalRecordModel.self).filter { !$0.isSoftDeleted }.map {
                Export.Record(exerciseId: $0.recordKey, kind: $0.kindRaw, value: $0.value, achievedAt: $0.achievedAt)
            },
            checkIns: all(RecoveryCheckInModel.self).filter { !$0.isSoftDeleted }.sorted { $0.date < $1.date }.map {
                Export.CheckIn(date: $0.date, sleep: $0.sleep, soreness: $0.soreness, energy: $0.energy)
            },
            planChanges: all(PlanChangeModel.self).filter { !$0.isSoftDeleted }.sorted { $0.createdAt < $1.createdAt }.map {
                Export.Change(date: $0.createdAt, summary: $0.summary)
            }
        )
    }

    /// Writes the export as pretty-printed JSON to a temporary file for sharing.
    static func writeExportFile(in context: ModelContext, now: Date = .now) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(makeExport(in: context, now: now))
        let day = now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appending(path: "Kinetix-export-\(day).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: Delete

    /// Permanently deletes all training data and settings on this device.
    /// (Milestone 7 also deletes the cloud account and its data.)
    static func deleteEverything(in context: ModelContext) {
        SampleData.eraseAll(in: context)
        for key in [BalanceService.lastAutoAdjustKey, DeveloperSettings.simulateGPSKey, DeveloperSettings.simulationSpeedKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: Units

    /// Changes units and refreshes the distances shown in already-planned run summaries.
    static func changeUnits(to units: UnitSystem, profile: UserProfileModel, in context: ModelContext) {
        var updated = profile.profile
        updated.units = units
        profile.profile = updated
        let sessions = (try? context.fetch(FetchDescriptor<PlannedSessionModel>())) ?? []
        for session in sessions where session.kind.discipline == .run {
            guard let meters = session.estimatedDistanceMeters else { continue }
            let distance = String(format: "%.1f", Units.distance(meters: meters, in: units)) + " " + Units.distanceUnitLabel(units)
            if let range = session.summary.range(of: " · ", options: .backwards) {
                session.summary = String(session.summary[..<range.lowerBound]) + " · " + distance
            } else {
                session.summary = distance
            }
        }
        try? context.save()
    }
}

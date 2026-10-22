import Foundation
import SwiftData

/// Sets up the on-device database. Everything is stored locally first, so the
/// app works fully offline; sync (Milestone 7) uploads changes when online.
enum Persistence {
    static let schema = Schema(versionedSchema: KinetixSchemaV1.self)

    /// The store couldn't be opened after an update, so it was set aside (kept as a backup next
    /// to the new one) and Kinetix started fresh. The app tells the user once.
    nonisolated(unsafe) static var recoveredFromBrokenStore = false

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, migrationPlan: KinetixMigrationPlan.self, configurations: [configuration])
        }
        // The Application Support folder doesn't exist on first launch; create it so the
        // store opens cleanly.
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, migrationPlan: KinetixMigrationPlan.self, configurations: [configuration])
        } catch {
            // A store made before versioning: open it the way it was made.
            if let container = try? ModelContainer(for: schema, configurations: [configuration]) { return container }
            #if DEBUG
            // Pre-release only: if the data model changed incompatibly during development,
            // start with a fresh store rather than crash.
            print("Kinetix: resetting incompatible development store: \(error)")
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
            #else
            // Never crash on every launch: keep the old store as a backup and start fresh
            // (synced data comes back from the account).
            let stamp = Int(Date().timeIntervalSince1970)
            for suffix in ["", "-shm", "-wal"] {
                let from = URL(fileURLWithPath: storeURL.path + suffix)
                let to = URL(fileURLWithPath: storeURL.deletingPathExtension().path + "-backup-\(stamp).store" + suffix)
                try? FileManager.default.moveItem(at: from, to: to)
            }
            recoveredFromBrokenStore = true
            #endif
            return try ModelContainer(for: schema, migrationPlan: KinetixMigrationPlan.self, configurations: [configuration])
        }
    }

    static var storeURL: URL {
        URL.applicationSupportDirectory.appending(path: "Kinetix.store")
    }
}

/// Version 1 of the database (the first App Store release). Additive changes (a new optional
/// property, or one with a default) need nothing. Anything else (renaming, removing or changing
/// the type of a stored property): copy these models into this enum as they were, add
/// KinetixSchemaV2 with the new ones and a MigrationStage to KinetixMigrationPlan.
enum KinetixSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [UserProfileModel.self,
        CoachingSettingsModel.self,
        TrainingPlanModel.self,
        PlannedSessionModel.self,
        PlanChangeModel.self,
        RunLogModel.self,
        StrengthLogModel.self,
        SetLogModel.self,
        ExerciseStateModel.self,
        PersonalRecordModel.self,
        RecoveryCheckInModel.self,
        RunTemplateModel.self,
        GymTemplateModel.self,
        CustomExerciseModel.self,
        RouteModel.self]
    }
}

enum KinetixMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [KinetixSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

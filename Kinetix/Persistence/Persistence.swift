import Foundation
import SwiftData

/// Sets up the on-device database. Everything is stored locally first, so the
/// app works fully offline; sync (Milestone 7) uploads changes when online.
enum Persistence {
    static let schema = Schema([
        UserProfileModel.self,
        CoachingSettingsModel.self,
        TrainingPlanModel.self,
        PlannedSessionModel.self,
        PlanChangeModel.self,
        RunLogModel.self,
        StrengthLogModel.self,
        SetLogModel.self,
        ExerciseStateModel.self,
        PersonalRecordModel.self,
        RecoveryCheckInModel.self
    ])

    static var storeURL: URL {
        URL.applicationSupportDirectory.appending(path: "Kinetix.store")
    }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
        // The Application Support folder doesn't exist on first launch; create it so the
        // store opens cleanly.
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            #if DEBUG
            // Pre-release only: if the data model changed incompatibly during development,
            // start with a fresh store rather than crash. Release builds never do this.
            print("Kinetix: resetting incompatible development store: \(error)")
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
            return try ModelContainer(for: schema, configurations: [configuration])
            #else
            throw error
            #endif
        }
    }
}

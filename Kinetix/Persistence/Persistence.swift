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

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

import Foundation
import SwiftData
import TrainingEngine

/// A saved custom run ("Threshold 2 × 10") for the Record tab. Synced to the account.
@Model
final class RunTemplateModel: SyncTracked {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    var name: String
    var typeRaw: String
    /// Encoded `[RunBlock]`.
    var blocksData: Data?
    var createdAt: Date
    var lastUsedAt: Date?

    init(workout: CustomRunWorkout, id: UUID = UUID(), now: Date = .now) {
        self.id = id
        self.updatedAt = now
        self.deletedAt = nil
        self.needsSync = true
        self.name = workout.name
        self.typeRaw = workout.type.rawValue
        self.blocksData = StoredJSON.encode(workout.blocks)
        self.createdAt = now
    }

    var workout: CustomRunWorkout {
        get {
            CustomRunWorkout(id: id, name: name, type: RecordRunType(rawValue: typeRaw) ?? .free,
                             blocks: StoredJSON.decode([RunBlock].self, from: blocksData) ?? [])
        }
        set {
            name = newValue.name
            typeRaw = newValue.type.rawValue
            blocksData = StoredJSON.encode(newValue.blocks)
        }
    }
}

/// A saved gym workout ("Push day") from the Record tab. Synced to the account.
@Model
final class GymTemplateModel: SyncTracked {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    var name: String
    /// Encoded `[GymTemplateItem]`.
    var itemsData: Data?
    var createdAt: Date
    var lastUsedAt: Date?

    init(name: String, items: [GymTemplateItem], id: UUID = UUID(), now: Date = .now) {
        self.id = id
        self.updatedAt = now
        self.deletedAt = nil
        self.needsSync = true
        self.name = name
        self.itemsData = StoredJSON.encode(items)
        self.createdAt = now
    }

    var items: [GymTemplateItem] {
        get { StoredJSON.decode([GymTemplateItem].self, from: itemsData) ?? [] }
        set { itemsData = StoredJSON.encode(newValue) }
    }
}

/// An exercise the user added to the library themselves. Synced to the account.
@Model
final class CustomExerciseModel: SyncTracked {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    var name: String
    var muscleRaw: String
    var loadingRaw: String
    var createdAt: Date

    init(name: String, muscle: MuscleGroup, loading: ExerciseLoading, id: UUID = UUID(), now: Date = .now) {
        self.id = id
        self.updatedAt = now
        self.deletedAt = nil
        self.needsSync = true
        self.name = name
        self.muscleRaw = muscle.rawValue
        self.loadingRaw = loading.rawValue
        self.createdAt = now
    }

    var exerciseId: String { "custom-\(id.uuidString.lowercased())" }

    var definition: ExerciseDefinition {
        let muscle = MuscleGroup(rawValue: muscleRaw) ?? .fullBody
        let region: BodyRegion = switch muscle {
        case .legs, .glutes, .fullBody: .lower
        case .core: .core
        default: .upper
        }
        return ExerciseDefinition(id: exerciseId, name: name, pattern: "custom", requires: .bodyweight,
                                  loading: ExerciseLoading(rawValue: loadingRaw) ?? .dumbbell, region: region,
                                  muscle: muscle, libraryOnly: true)
    }
}

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
    /// Encoded `[WorkoutBlock]`.
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
                             blocks: StoredJSON.decode([WorkoutBlock].self, from: blocksData) ?? [])
        }
        set {
            name = newValue.name
            typeRaw = newValue.type.rawValue
            blocksData = StoredJSON.encode(newValue.blocks)
        }
    }
}

import Foundation
import SwiftData

/// A completed run. Route and samples are stored as compact JSON blobs.
@Model
final class RunLogModel: SyncTracked {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    var plannedSessionId: UUID?
    var startedAt: Date
    var durationSeconds: Double
    var distanceMeters: Double
    var routeData: Data?
    var splitsData: Data?
    var heartRateData: Data?
    var averageHeartRate: Double?
    var timeInTargetSeconds: Double
    /// Session RPE 1-10.
    var effort: Double
    /// Session load = minutes × effort (sRPE).
    var load: Double
    var healthKitWorkoutId: UUID?
    var stravaActivityId: String?
    var title: String = ""
    /// False while the run is in progress (it's checkpointed every 30 s).
    var isFinished: Bool = false
    var finishedAt: Date?
    var maxHeartRate: Double?
    /// Seconds of work/steady running where pace was measured against a target.
    var targetedSeconds: Double = 0
    /// Encoded `[SegmentResult]`.
    var segmentsData: Data?
    var usedSimulatedGPS: Bool = false

    init(plannedSessionId: UUID?, startedAt: Date, id: UUID = UUID(), now: Date = .now) {
        self.id = id
        self.updatedAt = now
        self.deletedAt = nil
        self.needsSync = true
        self.plannedSessionId = plannedSessionId
        self.startedAt = startedAt
        self.durationSeconds = 0
        self.distanceMeters = 0
        self.timeInTargetSeconds = 0
        self.effort = 0
        self.load = 0
    }
}

/// A completed strength session and its sets.
@Model
final class StrengthLogModel: SyncTracked {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    var plannedSessionId: UUID?
    var startedAt: Date
    var durationSeconds: Double
    var effort: Double
    var load: Double
    var healthKitWorkoutId: UUID?
    var title: String = ""
    /// False while the workout is in progress (sets are saved as you go, so it can be resumed).
    var isFinished: Bool = false
    var finishedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \SetLogModel.session)
    var sets: [SetLogModel] = []

    init(plannedSessionId: UUID?, startedAt: Date, id: UUID = UUID(), now: Date = .now) {
        self.id = id
        self.updatedAt = now
        self.deletedAt = nil
        self.needsSync = true
        self.plannedSessionId = plannedSessionId
        self.startedAt = startedAt
        self.durationSeconds = 0
        self.effort = 0
        self.load = 0
    }

    /// Volume = Σ reps × weight (kg) over completed sets.
    var volumeKg: Double {
        sets.filter(\.isCompleted).reduce(0) { $0 + Double($1.actualReps) * $1.actualWeightKg }
    }

    var orderedSets: [SetLogModel] {
        sets.filter { !$0.isSoftDeleted }.sorted { ($0.exerciseOrder, $0.setIndex) < ($1.exerciseOrder, $1.setIndex) }
    }
}

@Model
final class SetLogModel: SyncTracked {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    var session: StrengthLogModel?
    var exerciseId: String
    var setIndex: Int
    var targetReps: Int
    var targetWeightKg: Double
    var actualReps: Int
    var actualWeightKg: Double
    var rpe: Double?
    var completedAt: Date?
    var progressionKey: String = ""
    var exerciseName: String = ""
    var exerciseOrder: Int = 0
    var repRangeLower: Int = 0
    var repRangeUpper: Int = 0
    var restSeconds: Int = 90
    /// Bodyweight exercises have no load.
    var isBodyweight: Bool = false

    var isCompleted: Bool { completedAt != nil }

    init(exerciseId: String, setIndex: Int, targetReps: Int, targetWeightKg: Double, id: UUID = UUID(), now: Date = .now) {
        self.id = id
        self.updatedAt = now
        self.deletedAt = nil
        self.needsSync = true
        self.exerciseId = exerciseId
        self.setIndex = setIndex
        self.targetReps = targetReps
        self.targetWeightKg = targetWeightKg
        // Pre-filled with targets for fast entry.
        self.actualReps = targetReps
        self.actualWeightKg = targetWeightKg
    }
}

/// Current progression state per exercise (working weight, stalls).
@Model
final class ExerciseStateModel: SyncTracked {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    /// `ExercisePrescription.progressionKey`: exercise id + role, e.g. "barbell-back-squat.main".
    @Attribute(.unique) var progressionKey: String = ""
    var exerciseId: String = ""
    var workingWeightKg: Double
    var repRangeLower: Int
    var repRangeUpper: Int
    var stallCount: Int
    /// "Added 2.5 kg: you hit 3×10 at RPE 8."
    var lastChangeReason: String?
    var lastChangedAt: Date?
    var exerciseName: String = ""

    init(progressionKey: String, exerciseId: String, workingWeightKg: Double, repRangeLower: Int, repRangeUpper: Int, id: UUID = UUID(), now: Date = .now) {
        self.id = id
        self.updatedAt = now
        self.deletedAt = nil
        self.needsSync = true
        self.progressionKey = progressionKey
        self.exerciseId = exerciseId
        self.workingWeightKg = workingWeightKg
        self.repRangeLower = repRangeLower
        self.repRangeUpper = repRangeUpper
        self.stallCount = 0
    }
}

@Model
final class PersonalRecordModel: SyncTracked {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    /// Exercise id, or a run distance key such as "run.5k".
    var recordKey: String
    /// e.g. "e1rm", "maxWeight", "time".
    var kindRaw: String
    var value: Double
    var achievedAt: Date

    init(recordKey: String, kindRaw: String, value: Double, achievedAt: Date, id: UUID = UUID(), now: Date = .now) {
        self.id = id
        self.updatedAt = now
        self.deletedAt = nil
        self.needsSync = true
        self.recordKey = recordKey
        self.kindRaw = kindRaw
        self.value = value
        self.achievedAt = achievedAt
    }
}

/// Optional daily recovery check-in (1-5 scales).
@Model
final class RecoveryCheckInModel: SyncTracked {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    var date: Date
    var sleep: Int
    var soreness: Int
    var energy: Int

    init(date: Date, sleep: Int, soreness: Int, energy: Int, id: UUID = UUID(), now: Date = .now) {
        self.id = id
        self.updatedAt = now
        self.deletedAt = nil
        self.needsSync = true
        self.date = date
        self.sleep = sleep
        self.soreness = soreness
        self.energy = energy
    }
}

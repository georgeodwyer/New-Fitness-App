import Foundation
import SwiftData
import TrainingEngine

/// A generated training plan. The outline (blocks) covers the whole horizon;
/// detailed sessions are generated about two weeks ahead.
@Model
final class TrainingPlanModel: SyncTracked {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    var goalRaw: String
    var startDate: Date
    var endDate: Date?
    /// Encoded outline (base/build/peak/taper blocks); format defined in Milestone 2.
    var blocksData: Data
    /// Engine version that generated this plan.
    var engineVersion: String
    var isActive: Bool

    @Relationship(deleteRule: .cascade, inverse: \PlannedSessionModel.plan)
    var sessions: [PlannedSessionModel] = []

    init(goal: TrainingGoal, startDate: Date, endDate: Date?, blocksData: Data = Data(), id: UUID = UUID(), now: Date = .now) {
        self.id = id
        self.updatedAt = now
        self.deletedAt = nil
        self.needsSync = true
        self.goalRaw = goal.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.blocksData = blocksData
        self.engineVersion = TrainingEngine.version
        self.isActive = true
    }
}

/// One session on the calendar (a run, a lift, cross-training or mobility).
@Model
final class PlannedSessionModel: SyncTracked {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    var plan: TrainingPlanModel?
    /// Start of the day the session is scheduled for.
    var date: Date
    var slotRaw: String
    var kindData: Data
    /// Key sessions are protected when the week is rebalanced.
    var isKey: Bool
    var statusRaw: String
    var statusChangedAt: Date?
    /// If swapped, what it was originally.
    var originalKindData: Data?
    /// One-sentence explanation of the last change, shown to the user.
    var changeReason: String?
    var plannedDurationMinutes: Double
    /// Expected effort 1-10, used for planned load.
    var plannedEffort: Double
    var runStructureData: Data?
    var strengthPrescriptionData: Data?

    init(
        date: Date,
        slot: SessionSlot,
        kind: SessionKind,
        isKey: Bool,
        plannedDurationMinutes: Double,
        plannedEffort: Double,
        runStructure: RunStructure? = nil,
        strength: StrengthPrescription? = nil,
        id: UUID = UUID(),
        now: Date = .now
    ) {
        self.id = id
        self.updatedAt = now
        self.deletedAt = nil
        self.needsSync = true
        self.date = date
        self.slotRaw = slot.rawValue
        self.kindData = StoredJSON.encode(kind)
        self.isKey = isKey
        self.statusRaw = SessionStatus.planned.rawValue
        self.plannedDurationMinutes = plannedDurationMinutes
        self.plannedEffort = plannedEffort
        self.runStructureData = runStructure.map { StoredJSON.encode($0) }
        self.strengthPrescriptionData = strength.map { StoredJSON.encode($0) }
    }

    var kind: SessionKind {
        get { StoredJSON.decode(SessionKind.self, from: kindData) ?? .mobility }
        set { kindData = StoredJSON.encode(newValue); touch() }
    }

    var slot: SessionSlot { SessionSlot(rawValue: slotRaw) ?? .morning }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .planned }
        set {
            statusRaw = newValue.rawValue
            statusChangedAt = .now
            touch()
        }
    }

    var runStructure: RunStructure? { StoredJSON.decode(RunStructure.self, from: runStructureData) }
    var strengthPrescription: StrengthPrescription? { StoredJSON.decode(StrengthPrescription.self, from: strengthPrescriptionData) }
}

/// A log of plan changes ("Moved your leg day to Thursday to protect Saturday's long run.").
@Model
final class PlanChangeModel: SyncTracked {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    var createdAt: Date
    var sessionId: UUID?
    var summary: String

    init(summary: String, sessionId: UUID? = nil, id: UUID = UUID(), now: Date = .now) {
        self.id = id
        self.updatedAt = now
        self.deletedAt = nil
        self.needsSync = true
        self.createdAt = now
        self.sessionId = sessionId
        self.summary = summary
    }
}

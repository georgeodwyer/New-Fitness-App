import Foundation
import SwiftData
import TrainingEngine
import KinetixSync

/// A stored model that syncs to the cloud as a `SyncRecord` (type + JSON payload).
protocol SyncableModel: PersistentModel, SyncTracked {
    associatedtype Payload: Codable
    static var syncType: String { get }
    var syncPayload: Payload { get }
    /// Writes downloaded values without marking the record as changed.
    func applySync(_ payload: Payload, context: ModelContext)
    /// A blank instance with the given id, filled in by `applySync`.
    static func makeForSync(id: UUID) -> Self
}

extension SyncableModel {
    func syncRecord() throws -> SyncRecord {
        SyncRecord(id: id, type: Self.syncType, updatedAt: updatedAt, deletedAt: deletedAt, payload: try JSONValue.from(syncPayload))
    }

    /// Applies a downloaded record (caller has already decided it's newer).
    func apply(_ record: SyncRecord, context: ModelContext) throws {
        applySync(try record.payload.decode(Payload.self), context: context)
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsSync = false
    }
}

/// Every synced type, in dependency order (plans before sessions, workouts before sets).
enum SyncRegistry {
    static let types: [any SyncableModel.Type] = [
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
        RecoveryCheckInModel.self,
        RunTemplateModel.self,
        GymTemplateModel.self,
        CustomExerciseModel.self,
        RouteModel.self
    ]
}

private func fetchOne<T: PersistentModel & SyncTracked>(_ type: T.Type, id: UUID?, in context: ModelContext) -> T? {
    guard let id else { return nil }
    return ((try? context.fetch(FetchDescriptor<T>())) ?? []).first { $0.id == id }
}

// MARK: - Profile & settings

extension UserProfileModel: SyncableModel {
    struct Payload: Codable {
        var profile: AthleteProfile
        var createdAt: Date
    }
    static var syncType: String { "profile" }
    var syncPayload: Payload { Payload(profile: profile, createdAt: createdAt) }

    func applySync(_ payload: Payload, context: ModelContext) {
        let p = payload.profile
        runningExperienceRaw = p.runningExperience.rawValue
        recentRaceData = p.recentRace.map { StoredJSON.encode($0) }
        liftingExperienceRaw = p.liftingExperience.rawValue
        liftEstimatesData = StoredJSON.encode(p.liftEstimates)
        goalRaw = p.goal.rawValue
        eventDate = p.eventDate
        trainingDaysData = StoredJSON.encode(p.trainingDays)
        doubleSessionDays = p.doubleSessionDays
        equipmentRaw = p.equipment.rawValue
        unitsRaw = p.units.rawValue
        weeklyRunMeters = p.weeklyRunMeters
        longestRecentRunMeters = p.longestRecentRunMeters
        racedRecently = p.racedRecently
        easyFirstWeek = p.easyFirstWeek
        easyFirstWeekRequestedAt = p.easyFirstWeekRequestedAt
        liftSessionsPerWeek = p.liftSessionsPerWeek
        splitCode = p.splitCode
        birthYear = p.birthYear
        heartRateZonesData = p.heartRateZones.map { StoredJSON.encode($0) }
        hyroxDivisionRaw = p.hyroxDivision?.rawValue
        exerciseSwapsData = p.exerciseSwaps.map { StoredJSON.encode($0) }
        planStartDate = p.planStartDate
        createdAt = payload.createdAt
    }

    static func makeForSync(id: UUID) -> UserProfileModel {
        UserProfileModel(profile: AthleteProfile(runningExperience: .beginner, liftingExperience: .beginner, goal: .balancedHybrid,
                                                 trainingDays: [], equipment: .fullGym), id: id)
    }
}

extension CoachingSettingsModel: SyncableModel {
    struct Payload: Codable {
        var paceCueDelaySeconds: Double
        var paceToleranceSecondsPerKm: Double
        var voiceIdentifier: String?
        var cueVolume: Double
        var paceCuesEnabled: Bool
        var splitAnnouncementsEnabled: Bool
        var segmentAnnouncementsEnabled: Bool
        var cuesDuringWarmUpCoolDown: Bool
        var dashboardLayoutData: Data?
    }
    static var syncType: String { "coachingSettings" }
    var syncPayload: Payload {
        Payload(paceCueDelaySeconds: paceCueDelaySeconds, paceToleranceSecondsPerKm: paceToleranceSecondsPerKm,
                voiceIdentifier: voiceIdentifier, cueVolume: cueVolume, paceCuesEnabled: paceCuesEnabled,
                splitAnnouncementsEnabled: splitAnnouncementsEnabled, segmentAnnouncementsEnabled: segmentAnnouncementsEnabled,
                cuesDuringWarmUpCoolDown: cuesDuringWarmUpCoolDown, dashboardLayoutData: dashboardLayoutData)
    }
    func applySync(_ p: Payload, context: ModelContext) {
        paceCueDelaySeconds = p.paceCueDelaySeconds
        paceToleranceSecondsPerKm = p.paceToleranceSecondsPerKm
        voiceIdentifier = p.voiceIdentifier
        cueVolume = p.cueVolume
        paceCuesEnabled = p.paceCuesEnabled
        splitAnnouncementsEnabled = p.splitAnnouncementsEnabled
        segmentAnnouncementsEnabled = p.segmentAnnouncementsEnabled
        cuesDuringWarmUpCoolDown = p.cuesDuringWarmUpCoolDown
        dashboardLayoutData = p.dashboardLayoutData
    }
    static func makeForSync(id: UUID) -> CoachingSettingsModel { CoachingSettingsModel(id: id) }
}

// MARK: - Plan

extension TrainingPlanModel: SyncableModel {
    struct Payload: Codable {
        var goalRaw: String
        var startDate: Date
        var endDate: Date?
        var blocksData: Data
        var engineVersion: String
        var isActive: Bool
        var generatedWeekCount: Int
        var weekNotesData: Data?
    }
    static var syncType: String { "trainingPlan" }
    var syncPayload: Payload {
        Payload(goalRaw: goalRaw, startDate: startDate, endDate: endDate, blocksData: blocksData,
                engineVersion: engineVersion, isActive: isActive, generatedWeekCount: generatedWeekCount,
                weekNotesData: weekNotesData)
    }
    func applySync(_ p: Payload, context: ModelContext) {
        goalRaw = p.goalRaw
        startDate = p.startDate
        endDate = p.endDate
        blocksData = p.blocksData
        engineVersion = p.engineVersion
        isActive = p.isActive
        generatedWeekCount = p.generatedWeekCount
        weekNotesData = p.weekNotesData
    }
    static func makeForSync(id: UUID) -> TrainingPlanModel {
        TrainingPlanModel(goal: .balancedHybrid, startDate: .now, endDate: nil, id: id)
    }
}

extension PlannedSessionModel: SyncableModel {
    struct Payload: Codable {
        var planId: UUID?
        var date: Date
        var slotRaw: String
        var kindData: Data
        var isKey: Bool
        var statusRaw: String
        var statusChangedAt: Date?
        var originalKindData: Data?
        var changeReason: String?
        var plannedDurationMinutes: Double
        var plannedEffort: Double
        var runStructureData: Data?
        var strengthPrescriptionData: Data?
        var title: String
        var summary: String
        var weekIndex: Int
        var estimatedDistanceMeters: Double?
    }
    static var syncType: String { "plannedSession" }
    var syncPayload: Payload {
        Payload(planId: plan?.id, date: date, slotRaw: slotRaw, kindData: kindData, isKey: isKey, statusRaw: statusRaw,
                statusChangedAt: statusChangedAt, originalKindData: originalKindData, changeReason: changeReason,
                plannedDurationMinutes: plannedDurationMinutes, plannedEffort: plannedEffort, runStructureData: runStructureData,
                strengthPrescriptionData: strengthPrescriptionData, title: title, summary: summary, weekIndex: weekIndex,
                estimatedDistanceMeters: estimatedDistanceMeters)
    }
    func applySync(_ p: Payload, context: ModelContext) {
        date = p.date
        slotRaw = p.slotRaw
        kindData = p.kindData
        isKey = p.isKey
        statusRaw = p.statusRaw
        statusChangedAt = p.statusChangedAt
        originalKindData = p.originalKindData
        changeReason = p.changeReason
        plannedDurationMinutes = p.plannedDurationMinutes
        plannedEffort = p.plannedEffort
        runStructureData = p.runStructureData
        strengthPrescriptionData = p.strengthPrescriptionData
        title = p.title
        summary = p.summary
        weekIndex = p.weekIndex
        estimatedDistanceMeters = p.estimatedDistanceMeters
        if let planId = p.planId, plan?.id != planId {
            plan = fetchOne(TrainingPlanModel.self, id: planId, in: context)
        }
    }
    static func makeForSync(id: UUID) -> PlannedSessionModel {
        PlannedSessionModel(date: .now, slot: .morning, kind: .mobility, isKey: false, plannedDurationMinutes: 0, plannedEffort: 0, id: id)
    }
}

extension PlanChangeModel: SyncableModel {
    struct Payload: Codable {
        var createdAt: Date
        var sessionId: UUID?
        var summary: String
        var causeRaw: String?
        var beforeData: Data?
        var afterData: Data?
        var triggersData: Data?
        var restoreData: Data?
        var undoneAt: Date?
    }
    static var syncType: String { "planChange" }
    var syncPayload: Payload {
        Payload(createdAt: createdAt, sessionId: sessionId, summary: summary, causeRaw: causeRaw,
                beforeData: beforeData, afterData: afterData, triggersData: triggersData,
                restoreData: restoreData, undoneAt: undoneAt)
    }
    func applySync(_ p: Payload, context: ModelContext) {
        createdAt = p.createdAt
        sessionId = p.sessionId
        summary = p.summary
        causeRaw = p.causeRaw ?? ChangeCause.other.rawValue
        beforeData = p.beforeData
        afterData = p.afterData
        triggersData = p.triggersData
        restoreData = p.restoreData
        undoneAt = p.undoneAt
    }
    static func makeForSync(id: UUID) -> PlanChangeModel { PlanChangeModel(summary: "", id: id) }
}

// MARK: - Logs

extension RunLogModel: SyncableModel {
    struct Payload: Codable {
        var plannedSessionId: UUID?
        var startedAt: Date
        var durationSeconds: Double
        var distanceMeters: Double
        var routeData: Data?
        var splitsData: Data?
        var heartRateData: Data?
        var averageHeartRate: Double?
        var maxHeartRate: Double?
        var timeInTargetSeconds: Double
        var targetedSeconds: Double
        var segmentsData: Data?
        var lapsData: Data?
        var effort: Double
        var load: Double
        var title: String
        var isFinished: Bool
        var finishedAt: Date?
        var usedSimulatedGPS: Bool
        var healthKitWorkoutId: UUID?
        var stravaActivityId: String?
        var runTypeRaw: String?
        var recordTypeRaw: String?
        var importSourceRaw: String?
    }
    static var syncType: String { "runLog" }
    var syncPayload: Payload {
        Payload(plannedSessionId: plannedSessionId, startedAt: startedAt, durationSeconds: durationSeconds, distanceMeters: distanceMeters,
                routeData: routeData, splitsData: splitsData, heartRateData: heartRateData, averageHeartRate: averageHeartRate,
                maxHeartRate: maxHeartRate, timeInTargetSeconds: timeInTargetSeconds, targetedSeconds: targetedSeconds,
                segmentsData: segmentsData, lapsData: lapsData, effort: effort, load: load, title: title, isFinished: isFinished, finishedAt: finishedAt,
                usedSimulatedGPS: usedSimulatedGPS, healthKitWorkoutId: healthKitWorkoutId, stravaActivityId: stravaActivityId,
                runTypeRaw: runTypeRaw, recordTypeRaw: recordTypeRaw, importSourceRaw: importSourceRaw)
    }
    func applySync(_ p: Payload, context: ModelContext) {
        plannedSessionId = p.plannedSessionId
        startedAt = p.startedAt
        durationSeconds = p.durationSeconds
        distanceMeters = p.distanceMeters
        routeData = p.routeData
        splitsData = p.splitsData
        heartRateData = p.heartRateData
        averageHeartRate = p.averageHeartRate
        maxHeartRate = p.maxHeartRate
        timeInTargetSeconds = p.timeInTargetSeconds
        targetedSeconds = p.targetedSeconds
        segmentsData = p.segmentsData
        lapsData = p.lapsData
        effort = p.effort
        load = p.load
        title = p.title
        isFinished = p.isFinished
        finishedAt = p.finishedAt
        usedSimulatedGPS = p.usedSimulatedGPS
        healthKitWorkoutId = p.healthKitWorkoutId
        stravaActivityId = p.stravaActivityId
        runTypeRaw = p.runTypeRaw
        recordTypeRaw = p.recordTypeRaw
        importSourceRaw = p.importSourceRaw
    }
    static func makeForSync(id: UUID) -> RunLogModel { RunLogModel(plannedSessionId: nil, startedAt: .now, id: id) }
}

extension StrengthLogModel: SyncableModel {
    struct Payload: Codable {
        var plannedSessionId: UUID?
        var startedAt: Date
        var durationSeconds: Double
        var effort: Double
        var load: Double
        var title: String
        var isFinished: Bool
        var finishedAt: Date?
        var healthKitWorkoutId: UUID?
        var stravaActivityId: String?
        var isRecorded: Bool?
        var activeSeconds: Double?
        var warmUpSeconds: Double?
        var templateId: UUID?
    }
    static var syncType: String { "strengthLog" }
    var syncPayload: Payload {
        Payload(plannedSessionId: plannedSessionId, startedAt: startedAt, durationSeconds: durationSeconds, effort: effort,
                load: load, title: title, isFinished: isFinished, finishedAt: finishedAt, healthKitWorkoutId: healthKitWorkoutId,
                stravaActivityId: stravaActivityId, isRecorded: isRecorded, activeSeconds: activeSeconds, warmUpSeconds: warmUpSeconds,
                templateId: templateId)
    }
    func applySync(_ p: Payload, context: ModelContext) {
        plannedSessionId = p.plannedSessionId
        startedAt = p.startedAt
        durationSeconds = p.durationSeconds
        effort = p.effort
        load = p.load
        title = p.title
        isFinished = p.isFinished
        finishedAt = p.finishedAt
        healthKitWorkoutId = p.healthKitWorkoutId
        stravaActivityId = p.stravaActivityId
        isRecorded = p.isRecorded ?? false
        activeSeconds = p.activeSeconds ?? 0
        warmUpSeconds = p.warmUpSeconds
        templateId = p.templateId
    }
    static func makeForSync(id: UUID) -> StrengthLogModel { StrengthLogModel(plannedSessionId: nil, startedAt: .now, id: id) }
}

extension SetLogModel: SyncableModel {
    struct Payload: Codable {
        var sessionId: UUID?
        var exerciseId: String
        var setIndex: Int
        var targetReps: Int
        var targetWeightKg: Double
        var actualReps: Int
        var actualWeightKg: Double
        var rpe: Double?
        var completedAt: Date?
        var progressionKey: String
        var exerciseName: String
        var exerciseOrder: Int
        var repRangeLower: Int
        var repRangeUpper: Int
        var restSeconds: Int
        var isBodyweight: Bool
        var activeSeconds: Double?
    }
    static var syncType: String { "setLog" }
    var syncPayload: Payload {
        Payload(sessionId: session?.id, exerciseId: exerciseId, setIndex: setIndex, targetReps: targetReps, targetWeightKg: targetWeightKg,
                actualReps: actualReps, actualWeightKg: actualWeightKg, rpe: rpe, completedAt: completedAt, progressionKey: progressionKey,
                exerciseName: exerciseName, exerciseOrder: exerciseOrder, repRangeLower: repRangeLower, repRangeUpper: repRangeUpper,
                restSeconds: restSeconds, isBodyweight: isBodyweight, activeSeconds: activeSeconds)
    }
    func applySync(_ p: Payload, context: ModelContext) {
        exerciseId = p.exerciseId
        setIndex = p.setIndex
        targetReps = p.targetReps
        targetWeightKg = p.targetWeightKg
        actualReps = p.actualReps
        actualWeightKg = p.actualWeightKg
        rpe = p.rpe
        completedAt = p.completedAt
        progressionKey = p.progressionKey
        exerciseName = p.exerciseName
        exerciseOrder = p.exerciseOrder
        repRangeLower = p.repRangeLower
        repRangeUpper = p.repRangeUpper
        restSeconds = p.restSeconds
        isBodyweight = p.isBodyweight
        activeSeconds = p.activeSeconds
        if let sessionId = p.sessionId, session?.id != sessionId {
            session = fetchOne(StrengthLogModel.self, id: sessionId, in: context)
        }
    }
    static func makeForSync(id: UUID) -> SetLogModel {
        SetLogModel(exerciseId: "", setIndex: 0, targetReps: 0, targetWeightKg: 0, id: id)
    }
}

extension ExerciseStateModel: SyncableModel {
    struct Payload: Codable {
        var progressionKey: String
        var exerciseId: String
        var exerciseName: String
        var workingWeightKg: Double
        var repRangeLower: Int
        var repRangeUpper: Int
        var stallCount: Int
        var lastChangeReason: String?
        var lastChangedAt: Date?
    }
    static var syncType: String { "exerciseState" }
    var syncPayload: Payload {
        Payload(progressionKey: progressionKey, exerciseId: exerciseId, exerciseName: exerciseName, workingWeightKg: workingWeightKg,
                repRangeLower: repRangeLower, repRangeUpper: repRangeUpper, stallCount: stallCount,
                lastChangeReason: lastChangeReason, lastChangedAt: lastChangedAt)
    }
    func applySync(_ p: Payload, context: ModelContext) {
        progressionKey = p.progressionKey
        exerciseId = p.exerciseId
        exerciseName = p.exerciseName
        workingWeightKg = p.workingWeightKg
        repRangeLower = p.repRangeLower
        repRangeUpper = p.repRangeUpper
        stallCount = p.stallCount
        lastChangeReason = p.lastChangeReason
        lastChangedAt = p.lastChangedAt
    }
    static func makeForSync(id: UUID) -> ExerciseStateModel {
        // Placeholder key keeps the unique constraint happy until the payload is applied.
        ExerciseStateModel(progressionKey: "sync-\(id.uuidString)", exerciseId: "", workingWeightKg: 0, repRangeLower: 0, repRangeUpper: 0, id: id)
    }
}

extension PersonalRecordModel: SyncableModel {
    struct Payload: Codable {
        var recordKey: String
        var kindRaw: String
        var value: Double
        var achievedAt: Date
    }
    static var syncType: String { "personalRecord" }
    var syncPayload: Payload { Payload(recordKey: recordKey, kindRaw: kindRaw, value: value, achievedAt: achievedAt) }
    func applySync(_ p: Payload, context: ModelContext) {
        recordKey = p.recordKey
        kindRaw = p.kindRaw
        value = p.value
        achievedAt = p.achievedAt
    }
    static func makeForSync(id: UUID) -> PersonalRecordModel {
        PersonalRecordModel(recordKey: "", kindRaw: "", value: 0, achievedAt: .now, id: id)
    }
}

extension RecoveryCheckInModel: SyncableModel {
    struct Payload: Codable {
        var date: Date
        var sleep: Int
        var soreness: Int
        var energy: Int
        var legSoreness: Int?
    }
    static var syncType: String { "recoveryCheckIn" }
    var syncPayload: Payload { Payload(date: date, sleep: sleep, soreness: soreness, energy: energy, legSoreness: legSoreness) }
    func applySync(_ p: Payload, context: ModelContext) {
        date = p.date
        sleep = p.sleep
        soreness = p.soreness
        energy = p.energy
        legSoreness = p.legSoreness
    }
    static func makeForSync(id: UUID) -> RecoveryCheckInModel {
        RecoveryCheckInModel(date: .now, sleep: 3, soreness: 3, energy: 3, id: id)
    }
}

// MARK: - Templates

extension RunTemplateModel: SyncableModel {
    struct Payload: Codable {
        var name: String
        var typeRaw: String
        var blocksData: Data?
        var createdAt: Date
        var lastUsedAt: Date?
    }
    static var syncType: String { "runTemplate" }
    var syncPayload: Payload {
        Payload(name: name, typeRaw: typeRaw, blocksData: blocksData, createdAt: createdAt, lastUsedAt: lastUsedAt)
    }
    func applySync(_ p: Payload, context: ModelContext) {
        name = p.name
        typeRaw = p.typeRaw
        blocksData = p.blocksData
        createdAt = p.createdAt
        lastUsedAt = p.lastUsedAt
    }
    static func makeForSync(id: UUID) -> RunTemplateModel {
        RunTemplateModel(workout: CustomRunWorkout(name: "", type: .free), id: id)
    }
}

extension GymTemplateModel: SyncableModel {
    struct Payload: Codable {
        var name: String
        var itemsData: Data?
        var createdAt: Date
        var lastUsedAt: Date?
    }
    static var syncType: String { "gymTemplate" }
    var syncPayload: Payload {
        Payload(name: name, itemsData: itemsData, createdAt: createdAt, lastUsedAt: lastUsedAt)
    }
    func applySync(_ p: Payload, context: ModelContext) {
        name = p.name
        itemsData = p.itemsData
        createdAt = p.createdAt
        lastUsedAt = p.lastUsedAt
    }
    static func makeForSync(id: UUID) -> GymTemplateModel {
        GymTemplateModel(name: "", items: [], id: id)
    }
}

extension CustomExerciseModel: SyncableModel {
    struct Payload: Codable {
        var name: String
        var muscleRaw: String
        var loadingRaw: String
        var createdAt: Date
    }
    static var syncType: String { "customExercise" }
    var syncPayload: Payload {
        Payload(name: name, muscleRaw: muscleRaw, loadingRaw: loadingRaw, createdAt: createdAt)
    }
    func applySync(_ p: Payload, context: ModelContext) {
        name = p.name
        muscleRaw = p.muscleRaw
        loadingRaw = p.loadingRaw
        createdAt = p.createdAt
    }
    static func makeForSync(id: UUID) -> CustomExerciseModel {
        CustomExerciseModel(name: "", muscle: .fullBody, loading: .dumbbell, id: id)
    }
}

extension RouteModel: SyncableModel {
    struct Payload: Codable {
        var name: String
        var waypointsData: Data?
        var pathData: Data?
        var instructionsData: Data?
        var followsRoads: Bool
        var distanceMeters: Double
        var createdAt: Date
        var lastUsedAt: Date?
    }
    static var syncType: String { "route" }
    var syncPayload: Payload {
        Payload(name: name, waypointsData: waypointsData, pathData: pathData, instructionsData: instructionsData,
                followsRoads: followsRoads, distanceMeters: distanceMeters, createdAt: createdAt, lastUsedAt: lastUsedAt)
    }
    func applySync(_ p: Payload, context: ModelContext) {
        name = p.name
        waypointsData = p.waypointsData
        pathData = p.pathData
        instructionsData = p.instructionsData
        followsRoads = p.followsRoads
        distanceMeters = p.distanceMeters
        createdAt = p.createdAt
        lastUsedAt = p.lastUsedAt
    }
    static func makeForSync(id: UUID) -> RouteModel {
        RouteModel(route: PlannedRoute(id: id, name: "", waypoints: [], path: []))
    }
}

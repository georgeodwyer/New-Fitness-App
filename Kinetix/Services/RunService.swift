import Foundation
import SwiftData
import TrainingEngine

/// Saves runs: a checkpoint every so often while running (so a crash doesn't lose
/// the run), and the final record with effort and load.
@MainActor
enum RunService {
    static func begin(planned: PlannedSessionModel?, title: String, simulated: Bool, recordType: RecordRunType? = nil,
                      in context: ModelContext, now: Date = .now) -> RunLogModel {
        let log = RunLogModel(plannedSessionId: planned?.id, startedAt: now)
        log.title = title
        log.usedSimulatedGPS = simulated
        log.recordTypeRaw = recordType?.rawValue
        if let type = recordType?.sessionType {
            log.runTypeRaw = type.rawValue
        } else if case .run(let type)? = planned?.kind {
            log.runTypeRaw = type.rawValue
        }
        context.insert(log)
        try? context.save()
        return log
    }

    /// Copies the engine's summary into the log.
    static func record(_ summary: RunSummary, into log: RunLogModel, now: Date = .now) {
        log.durationSeconds = summary.durationSeconds
        log.distanceMeters = summary.distanceMeters
        log.routeData = StoredJSON.encode(summary.route)
        log.splitsData = StoredJSON.encode(summary.splits)
        log.segmentsData = StoredJSON.encode(summary.segments)
        log.lapsData = summary.laps.flatMap { $0.isEmpty ? nil : StoredJSON.encode($0) }
        log.averageHeartRate = summary.averageHeartRate
        log.maxHeartRate = summary.maxHeartRate
        log.heartRateData = summary.heartRateSamples.isEmpty ? nil : StoredJSON.encode(summary.heartRateSamples)
        log.timeInTargetSeconds = summary.timeInTargetSeconds
        log.targetedSeconds = summary.targetedSeconds
        log.touch(now: now)
    }

    static func checkpoint(_ summary: RunSummary, into log: RunLogModel, in context: ModelContext) {
        record(summary, into: log)
        try? context.save()
    }

    static func finish(_ summary: RunSummary, log: RunLogModel, planned: PlannedSessionModel?, effort: Double, in context: ModelContext, now: Date = .now) {
        record(summary, into: log, now: now)
        log.effort = effort
        log.load = SessionLoad.srpe(durationSeconds: summary.durationSeconds, effort: effort)
        log.isFinished = true
        log.finishedAt = now
        planned?.status = .completed
        try? context.save()
        SyncService.shared.requestSync()
        ActivityExportService.runFinished(log, in: context)
    }

    /// A run that was recording when Kinetix stopped (closed by iOS, out of battery or a crash):
    /// unfinished, at least a minute long, and not checkpointed in the last two minutes.
    static func interrupted(in context: ModelContext, excluding activeLogId: UUID? = nil, now: Date = .now) -> RunLogModel? {
        let descriptor = FetchDescriptor<RunLogModel>(predicate: #Predicate { !$0.isFinished && $0.deletedAt == nil })
        return ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.id != activeLogId && $0.durationSeconds >= 60 && now.timeIntervalSince($0.updatedAt) > 120 }
            .max { $0.startedAt < $1.startedAt }
    }

    /// Saves an interrupted run as it was at its last checkpoint, with the session's usual
    /// effort (it can be changed afterwards on the run).
    static func saveInterrupted(_ log: RunLogModel, in context: ModelContext) {
        let plannedId = log.plannedSessionId
        let planned = plannedId.flatMap { id in
            try? context.fetch(FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.id == id })).first
        }
        let effort = planned?.plannedEffort ?? log.recordType?.typicalEffort ?? 5
        log.effort = effort
        log.load = SessionLoad.srpe(durationSeconds: log.durationSeconds, effort: effort)
        log.isFinished = true
        log.finishedAt = log.startedAt.addingTimeInterval(log.durationSeconds)
        log.touch()
        planned?.status = .completed
        try? context.save()
        SyncService.shared.requestSync()
        ActivityExportService.runFinished(log, in: context)
    }

    static func discard(_ log: RunLogModel, in context: ModelContext) {
        context.delete(log)
        try? context.save()
    }
}

extension RunService {
    /// Renames a finished run and/or changes its effort (which changes its training load).
    static func update(_ log: RunLogModel, title: String, effort: Double, in context: ModelContext) {
        log.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? log.title : title
        log.effort = effort
        log.load = SessionLoad.srpe(durationSeconds: log.durationSeconds, effort: effort)
        log.touch()
        try? context.save()
        SyncService.shared.requestSync()
    }

    /// Removes a run from Kinetix (and its training load). A planned session it completed
    /// goes back to planned. Copies already in Apple Health or on Strava are left alone.
    static func delete(_ log: RunLogModel, in context: ModelContext) {
        PlanService.reopen(sessionId: log.plannedSessionId, in: context)
        log.softDelete()
        try? context.save()
        SyncService.shared.requestSync()
    }
}

extension RunLogModel {
    var heartRateSamples: [HeartRateSample] { StoredJSON.decode([HeartRateSample].self, from: heartRateData) ?? [] }
    var runType: RunSessionType? { runTypeRaw.flatMap(RunSessionType.init(rawValue:)) }
    var recordType: RecordRunType? { recordTypeRaw.flatMap(RecordRunType.init(rawValue:)) }
    /// "Recorded" for Record-tab runs, "Planned" for plan sessions.
    var sourceTag: String? {
        if isImportedFromStrava { return "From Strava" }
        if isFromGarmin { return "Garmin" }
        if recordTypeRaw != nil { return "Recorded" }
        return plannedSessionId != nil ? "Planned" : nil
    }
    /// Recorded elsewhere and brought in from Strava (never sent back to Strava or Health).
    var isImportedFromStrava: Bool { importSourceRaw == "strava" }
    /// Recorded on the Kinetix Garmin app: Garmin Connect already has it (and sends it on to
    /// Strava and Health if you've linked them), so Kinetix doesn't upload it again.
    var isFromGarmin: Bool { importSourceRaw == "garmin" }
    /// Simulated GPS runs are practice data: shown, but left out of totals and best efforts.
    var countsTowardsHistory: Bool { isFinished && !isSoftDeleted && !usedSimulatedGPS }
    var route: [RoutePoint] { StoredJSON.decode([RoutePoint].self, from: routeData) ?? [] }
    var splits: [Split] { StoredJSON.decode([Split].self, from: splitsData) ?? [] }
    var laps: [Lap] { StoredJSON.decode([Lap].self, from: lapsData) ?? [] }
    var segmentResults: [SegmentResult] { StoredJSON.decode([SegmentResult].self, from: segmentsData) ?? [] }
    var averagePace: Pace? { distanceMeters > 50 && durationSeconds > 0 ? Pace(metersPerSecond: distanceMeters / durationSeconds) : nil }
}

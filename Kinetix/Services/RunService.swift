import Foundation
import SwiftData
import TrainingEngine

/// Saves runs: a checkpoint every so often while running (so a crash doesn't lose
/// the run), and the final record with effort and load.
@MainActor
enum RunService {
    static func begin(planned: PlannedSessionModel?, title: String, simulated: Bool, in context: ModelContext, now: Date = .now) -> RunLogModel {
        let log = RunLogModel(plannedSessionId: planned?.id, startedAt: now)
        log.title = title
        log.usedSimulatedGPS = simulated
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
        log.averageHeartRate = summary.averageHeartRate
        log.maxHeartRate = summary.maxHeartRate
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
    }

    static func discard(_ log: RunLogModel, in context: ModelContext) {
        context.delete(log)
        try? context.save()
    }
}

extension RunLogModel {
    var route: [RoutePoint] { StoredJSON.decode([RoutePoint].self, from: routeData) ?? [] }
    var splits: [Split] { StoredJSON.decode([Split].self, from: splitsData) ?? [] }
    var segmentResults: [SegmentResult] { StoredJSON.decode([SegmentResult].self, from: segmentsData) ?? [] }
    var averagePace: Pace? { distanceMeters > 50 && durationSeconds > 0 ? Pace(metersPerSecond: distanceMeters / durationSeconds) : nil }
}

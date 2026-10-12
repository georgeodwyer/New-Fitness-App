import Foundation
import SwiftData
import KinetixSync
import TrainingEngine

/// Sends finished sessions to Apple Health and Strava, and retries anything that couldn't
/// be sent (offline, Strava busy) the next time the app opens.
@MainActor
enum ActivityExportService {
    /// Sessions currently being sent, so a retry never doubles up with the first attempt.
    private static var inFlight: Set<UUID> = []
    /// Only sessions finished in the last week are retried automatically.
    static let retryWindow: TimeInterval = 7 * 24 * 3600

    static func runFinished(_ log: RunLogModel, in context: ModelContext) {
        Task { await export(run: log, in: context) }
    }

    static func strengthFinished(_ log: StrengthLogModel, units: UnitSystem, in context: ModelContext) {
        Task { await export(strength: log, units: units, in: context) }
    }

    static func export(run log: RunLogModel, in context: ModelContext, settings: IntegrationSettings = .shared) async {
        // Simulated GPS runs are practice data: keep them out of Health and Strava.
        guard log.isFinished, !log.isSoftDeleted, !log.usedSimulatedGPS, !inFlight.contains(log.id) else { return }
        inFlight.insert(log.id)
        defer { inFlight.remove(log.id) }
        var changed = false

        if shouldSaveToHealth(finishedAt: log.finishedAt, existing: log.healthKitWorkoutId, settings: settings),
           let id = try? await HealthService.shared.saveRun(log) {
            log.healthKitWorkoutId = id
            changed = true
        }

        let failureKey = "strava.\(log.id.uuidString)"
        if settings.stravaUploadRuns, log.stravaActivityId == nil, settings.uploadFailures[failureKey] == nil,
           isAfter(log.finishedAt, settings.stravaConnectedAt), StravaService.shared.isConnected {
            do {
                log.stravaActivityId = try await StravaService.shared.upload(run: log)
                changed = true
            } catch let error as StravaError where !error.isTransient && error != .notConnected {
                settings.uploadFailures[failureKey] = error.localizedDescription
            } catch {
                // Transient: retried next time the app opens.
            }
        }
        save(log, changed: changed, in: context)
    }

    static func export(strength log: StrengthLogModel, units: UnitSystem, in context: ModelContext, settings: IntegrationSettings = .shared) async {
        guard log.isFinished, !log.isSoftDeleted, !inFlight.contains(log.id) else { return }
        inFlight.insert(log.id)
        defer { inFlight.remove(log.id) }
        var changed = false

        if shouldSaveToHealth(finishedAt: log.finishedAt, existing: log.healthKitWorkoutId, settings: settings),
           let id = try? await HealthService.shared.saveStrength(log) {
            log.healthKitWorkoutId = id
            changed = true
        }

        let failureKey = "strava.\(log.id.uuidString)"
        if settings.stravaUploadLifts, log.stravaActivityId == nil, settings.uploadFailures[failureKey] == nil,
           isAfter(log.finishedAt, settings.stravaConnectedAt), StravaService.shared.isConnected {
            do {
                log.stravaActivityId = try await StravaService.shared.upload(strength: log, units: units)
                changed = true
            } catch let error as StravaError where !error.isTransient && error != .notConnected {
                settings.uploadFailures[failureKey] = error.localizedDescription
            } catch {}
        }
        save(log, changed: changed, in: context)
    }

    /// Retries recent sessions that haven't reached Health or Strava yet.
    static func retryPending(in context: ModelContext, units: UnitSystem, now: Date = .now) async {
        let settings = IntegrationSettings.shared
        guard settings.healthEnabled || StravaService.shared.isConnected else { return }
        let since = now.addingTimeInterval(-retryWindow)
        let runs = (try? context.fetch(FetchDescriptor<RunLogModel>(predicate: #Predicate { $0.isFinished && $0.startedAt >= since }))) ?? []
        for run in runs where run.healthKitWorkoutId == nil || run.stravaActivityId == nil {
            await export(run: run, in: context)
        }
        let lifts = (try? context.fetch(FetchDescriptor<StrengthLogModel>(predicate: #Predicate { $0.isFinished && $0.startedAt >= since }))) ?? []
        for lift in lifts where lift.healthKitWorkoutId == nil || lift.stravaActivityId == nil {
            await export(strength: lift, units: units, in: context)
        }
    }

    private static func shouldSaveToHealth(finishedAt: Date?, existing: UUID?, settings: IntegrationSettings) -> Bool {
        existing == nil && settings.healthEnabled && HealthService.shared.canSaveWorkouts && isAfter(finishedAt, settings.healthConnectedAt)
    }

    /// Only sessions finished after connecting are sent (connecting doesn't back-fill history).
    private static func isAfter(_ finishedAt: Date?, _ connectedAt: Date?) -> Bool {
        guard let finishedAt, let connectedAt else { return false }
        return finishedAt >= connectedAt
    }

    private static func save(_ log: some SyncTracked, changed: Bool, in context: ModelContext) {
        guard changed else { return }
        log.touch()
        try? context.save()
        SyncService.shared.requestSync()
    }
}

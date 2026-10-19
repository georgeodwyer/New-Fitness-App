import Foundation
import SwiftData
import WatchConnectivity
import TrainingEngine

/// Keeps the Apple Watch app up to date (planned runs, saved workouts, units, coaching
/// settings) and saves runs recorded on the watch: history, load, plan ticked off, and
/// Strava (the watch has already saved the workout to Apple Health).
@MainActor
final class WatchSyncService: NSObject {
    static let shared = WatchSyncService()

    private var container: ModelContainer?
    /// The last plan sent, so an unchanged plan isn't sent again.
    private var lastSentPlan: Data?

    /// Called at launch.
    func configure(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private var canSend: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated && WCSession.default.isWatchAppInstalled
    }

    // MARK: Plan → watch

    /// Sends the next week's runs and saved workouts (only if something changed).
    func sendPlan(now: Date = .now) {
        guard canSend, let context = container?.mainContext else { return }
        let plan = Self.makePlan(in: context, now: now)
        // Compare without the timestamp, which always differs.
        var comparable = plan
        comparable.generatedAt = .distantPast
        let fingerprint = comparable.encoded()
        guard fingerprint != lastSentPlan else { return }
        do {
            try WCSession.default.updateApplicationContext(["plan": plan.encoded()])
            lastSentPlan = fingerprint
        } catch {
            // Tried again next time the app opens.
        }
    }

    /// The runs the watch can start: planned runs from today for 7 days, then saved workouts.
    static func makePlan(in context: ModelContext, now: Date) -> WatchPlan {
        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 7, to: today) ?? now
        let sessions = ((try? context.fetch(FetchDescriptor<PlannedSessionModel>(sortBy: [SortDescriptor(\.date)]))) ?? [])
            .filter {
                !$0.isSoftDeleted && $0.date >= today && $0.date < end && $0.kind.discipline == .run
                    && ($0.status == .planned || $0.status == .swapped) && ($0.plan?.isActive ?? true)
            }
        let profile = ((try? context.fetch(FetchDescriptor<UserProfileModel>())) ?? []).first { !$0.isSoftDeleted }
        let units = profile?.units ?? UnitPreference.stored
        let planned = sessions.map { session in
            WatchRunOption(id: session.id, source: .planned, title: session.title,
                           detail: "\(session.summary) · \(Int(session.plannedDurationMinutes)) min",
                           date: session.date, structure: session.runStructure, typicalEffort: session.plannedEffort)
        }
        let templates = ((try? context.fetch(FetchDescriptor<RunTemplateModel>())) ?? [])
            .filter { !$0.isSoftDeleted }
            .sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
            .prefix(10)
            .map { template in
                let workout = template.workout
                return WatchRunOption(id: template.id, source: .template, title: workout.name,
                                      detail: workout.summary(units: units), structure: workout.structure,
                                      recordType: workout.type.rawValue, typicalEffort: workout.type.typicalEffort)
            }
        let settings = ((try? context.fetch(FetchDescriptor<CoachingSettingsModel>())) ?? []).first { !$0.isSoftDeleted }
        let coaching = CoachingConfig(
            paceCueDelaySeconds: settings?.paceCueDelaySeconds ?? 20,
            toleranceSecondsPerKm: settings?.paceToleranceSecondsPerKm ?? 10,
            paceCuesEnabled: settings?.paceCuesEnabled ?? true,
            splitAnnouncementsEnabled: settings?.splitAnnouncementsEnabled ?? true,
            segmentAnnouncementsEnabled: settings?.segmentAnnouncementsEnabled ?? true,
            cuesDuringWarmUpCoolDown: settings?.cuesDuringWarmUpCoolDown ?? false,
            units: units
        )
        return WatchPlan(generatedAt: now, units: units, coaching: coaching, runs: planned + Array(templates))
    }

    // MARK: Watch → runs

    /// Saves a run from the watch. Returns the saved run, or nil if it was already saved.
    @discardableResult
    static func save(_ result: WatchRunResult, in context: ModelContext) -> RunLogModel? {
        let id = result.id
        let existing = (try? context.fetch(FetchDescriptor<RunLogModel>(predicate: #Predicate { $0.id == id }))) ?? []
        guard existing.isEmpty else { return nil }

        var planned: PlannedSessionModel?
        if result.option.source == .planned {
            let plannedId = result.option.id
            planned = try? context.fetch(FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.id == plannedId })).first
        }
        let recordType = result.option.recordType.flatMap(RecordRunType.init(rawValue:))
        let log = RunLogModel(plannedSessionId: planned?.id, startedAt: result.startedAt, id: result.id)
        log.title = result.option.title
        log.recordTypeRaw = planned == nil ? (recordType ?? .free).rawValue : nil
        if let type = recordType?.sessionType {
            log.runTypeRaw = type.rawValue
        } else if case .run(let type)? = planned?.kind {
            log.runTypeRaw = type.rawValue
        }
        log.healthKitWorkoutId = result.healthKitWorkoutId
        context.insert(log)
        RunService.finish(result.summary, log: log, planned: planned, effort: result.effort, in: context, now: result.finishedAt)
        return log
    }

    fileprivate func receive(fileAt url: URL) {
        guard let data = try? Data(contentsOf: url), let result = WatchRunResult.decode(data),
              let context = container?.mainContext else { return }
        if Self.save(result, in: context) != nil {
            WidgetSnapshotService.update(in: context)
            sendPlan()
        }
    }
}

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.sendPlan() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another watch: reconnect.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.lastSentPlan = nil
            self.sendPlan()
        }
    }

    /// Messages during a mirrored run, when the direct workout link isn't up.
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in WatchMirrorService.shared.receive(messageData) }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The file is deleted when this returns: copy it first.
        let copy = FileManager.default.temporaryDirectory.appending(path: "watch-\(UUID().uuidString).json")
        try? FileManager.default.copyItem(at: file.fileURL, to: copy)
        Task { @MainActor in
            self.receive(fileAt: copy)
            try? FileManager.default.removeItem(at: copy)
        }
    }
}

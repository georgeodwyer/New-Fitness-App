import Foundation
import ActivityKit
import SwiftData
import WidgetKit
import TrainingEngine

/// The workout currently on screen, so the lock-screen Pause button can reach it.
@MainActor
final class ActiveWorkout {
    static let shared = ActiveWorkout()
    var togglePause: (() -> Void)?
}

/// Starts, updates and ends the lock-screen / Dynamic Island view of a workout.
/// Updates are throttled (iOS limits how often they can change) except when something
/// important changes, like pausing, a new step or a pace warning.
@MainActor
final class WorkoutActivityController {
    static let shared = WorkoutActivityController()

    private var activity: Activity<WorkoutActivityAttributes>?
    private var lastState: WorkoutActivityAttributes.ContentState?
    private var lastUpdate = Date.distantPast
    private static let minimumInterval: TimeInterval = 5

    var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled && !LaunchOptions().isUITesting }

    func start(title: String, kind: String, state: WorkoutActivityAttributes.ContentState) {
        guard isEnabled else { return }
        end()
        do {
            activity = try Activity.request(attributes: WorkoutActivityAttributes(title: title, kind: kind),
                                            content: ActivityContent(state: state, staleDate: nil))
            lastState = state
            lastUpdate = .now
        } catch {
            activity = nil
        }
    }

    /// `important` skips the throttle (pause/resume, new step, pace status change).
    func update(_ state: WorkoutActivityAttributes.ContentState, important: Bool = false) {
        guard let activity, state != lastState else { return }
        guard important || Date.now.timeIntervalSince(lastUpdate) >= Self.minimumInterval else { return }
        lastState = state
        lastUpdate = .now
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end(final state: WorkoutActivityAttributes.ContentState? = nil) {
        guard let activity else { return }
        self.activity = nil
        lastState = nil
        let content = state.map { ActivityContent(state: $0, staleDate: nil) }
        Task { await activity.end(content, dismissalPolicy: .immediate) }
    }
}

extension WorkoutActivityAttributes.ContentState {
    /// Lock-screen state for a run, from the engine's snapshot.
    @MainActor
    static func run(_ snapshot: RunSnapshot, units: UnitSystem, now: Date) -> Self {
        let format = DisplayFormat(units: units)
        let status: String? = switch snapshot.paceStatus {
        case .onTarget?: "onTarget"
        case .tooFast?: "tooFast"
        case .tooSlow?: "tooSlow"
        case nil: nil
        }
        var step: String?
        if let segment = snapshot.segment, snapshot.segmentIndex != nil {
            step = segment.label ?? segment.kind.builderName
        }
        return Self(
            mode: snapshot.isPaused ? .paused : .running,
            timerStart: snapshot.isPaused ? nil : now.addingTimeInterval(-snapshot.elapsedSeconds),
            elapsedSeconds: snapshot.elapsedSeconds,
            distance: format.distance(snapshot.distanceMeters, decimals: 2),
            pace: snapshot.currentPace.map { Units.formatPace($0, units: units) },
            target: snapshot.segment?.targetPace.map { format.paceRange($0) },
            paceStatus: status,
            step: step,
            stepDetail: snapshot.segmentRemaining.map { format.segmentLength($0) + " left" },
            heartRate: snapshot.heartRate.map { Int($0.rounded()) }
        )
    }
}

/// Saves what the home and lock-screen widgets show, then asks them to refresh.
@MainActor
enum WidgetSnapshotService {
    static func update(in context: ModelContext, now: Date = .now) {
        func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        let profile = all(UserProfileModel.self).first { !$0.isSoftDeleted }
        let units = profile?.units ?? UnitPreference.stored
        let format = DisplayFormat(units: units)
        let sessions = all(PlannedSessionModel.self).filter { !$0.isSoftDeleted && ($0.plan?.isActive ?? true) }
        let integrations = IntegrationSettings.shared
        let data = DashboardService.make(sessions: sessions, runs: all(RunLogModel.self), lifts: all(StrengthLogModel.self),
                                         checkIns: all(RecoveryCheckInModel.self), profile: profile?.profile,
                                         external: integrations.loadWorkouts, health: HealthInputs.current, now: now)
        let calendar = Calendar.kinetix
        let today = sessions.filter { calendar.isDate($0.date, inSameDayAs: now) }
            .sorted { $0.slot == .morning && $1.slot == .evening }
            .map {
                WidgetSnapshot.Session(id: $0.id, title: $0.title, detail: "\($0.summary) · \(Int($0.plannedDurationMinutes)) min",
                                       symbol: $0.kind.symbolName,
                                       discipline: $0.kind.discipline == .run ? "run" : $0.kind.discipline == .strength ? "strength" : "other",
                                       isDone: $0.status == .completed)
            }
        let adherence = data.adherence
        let snapshot = WidgetSnapshot(
            hasPlan: profile != nil,
            today: today,
            sessionsDone: adherence.completed,
            sessionsPlanned: adherence.total,
            runDone: format.distance(data.actualRunMeters, decimals: 0),
            runPlanned: data.plannedRunMeters > 0 ? format.distance(data.plannedRunMeters, decimals: 0) : "",
            runFraction: data.plannedRunMeters > 0 ? data.actualRunMeters / data.plannedRunMeters : 0,
            liftDone: format.volume(data.actualLiftVolumeKg),
            liftPlanned: data.plannedLiftVolumeKg > 0 ? format.volume(data.plannedLiftVolumeKg) : "",
            liftFraction: data.plannedLiftVolumeKg > 0 ? data.actualLiftVolumeKg / data.plannedLiftVolumeKg : 0,
            loadRatio: data.load.combined.ratio,
            loadZone: data.load.combined.status.rawValue,
            loadTitle: data.load.combined.status.title,
            strain: (data.strain.today.strain * 10).rounded() / 10,
            strainLow: (data.strain.target.low * 10).rounded() / 10,
            strainHigh: (data.strain.target.high * 10).rounded() / 10,
            recovery: data.strain.recovery?.score,
            updatedAt: now
        )
        let saved = WidgetSnapshot.load()
        var previous = saved
        previous?.updatedAt = now
        // Save when something changed, or on a new day (widgets ignore a snapshot from an earlier day).
        let savedToday = saved.map { Calendar.current.isDate($0.updatedAt, inSameDayAs: now) } ?? false
        guard snapshot != previous || !savedToday else { return }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

import Foundation
import HealthKit
import WatchConnectivity
import TrainingEngine

/// Shows a run recorded on the phone live on the Apple Watch. When a run starts the phone
/// opens the Kinetix watch app; the watch starts a workout session (which keeps it awake and
/// reads heart rate) and mirrors it back here, giving a direct link for the run screen,
/// the watch's buttons and its heart rate. If that link isn't up, messages go through
/// WatchConnectivity instead. The phone stays in charge: it records and saves the run.
@MainActor
final class WatchMirrorService: NSObject {
    static let shared = WatchMirrorService()

    /// What the run on the phone needs to hear from the watch.
    struct Handlers {
        var command: @MainActor (MirrorCommand) -> Void
        var heartRate: @MainActor (Double, Date) -> Void
    }

    private let healthStore = HKHealthStore()
    private var mirroredSession: HKWorkoutSession?
    private var runId: UUID?
    private var handlers: Handlers?

    /// Called at launch: the watch's mirrored session can arrive at any time (even with the
    /// app in the background), so the handler must be set early.
    func configure() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthStore.workoutSessionMirroringStartHandler = { session in
            Task { @MainActor in WatchMirrorService.shared.attach(session) }
        }
    }

    /// A paired watch with Kinetix on it, and the setting on.
    var isAvailable: Bool {
        guard IntegrationSettings.shared.mirrorRunsToWatch, WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }

    var isMirroring: Bool { runId != nil }

    // MARK: Run lifecycle (called by the phone's run)

    /// Opens the watch app for this run. Returns false if there's no watch to use.
    @discardableResult
    func begin(runId: UUID, handlers: Handlers) -> Bool {
        guard isAvailable else { return false }
        self.runId = runId
        self.handlers = handlers
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        healthStore.startWatchApp(with: configuration) { _, _ in
            // If the watch can't be woken (locked, off the wrist), the run carries on without
            // it; frames sent through WatchConnectivity still reach it if the app is opened.
        }
        return true
    }

    /// Sends the run screen to the watch.
    func publish(_ frame: MirrorFrame) {
        guard frame.runId == runId else { return }
        send(.frame(frame))
    }

    /// The run is over: the watch stops and goes back to its list.
    func end(saved: Bool) {
        guard let runId else { return }
        send(.ended(runId: runId, saved: saved))
        self.runId = nil
        handlers = nil
        mirroredSession = nil
    }

    // MARK: Link

    private func attach(_ session: HKWorkoutSession) {
        session.delegate = self
        mirroredSession = session
    }

    private func send(_ message: MirrorMessage) {
        let data = message.encoded()
        if let mirroredSession {
            mirroredSession.sendToRemoteWorkoutSession(data: data) { success, _ in
                guard !success else { return }
                Task { @MainActor in WatchMirrorService.shared.sendByWatchConnectivity(data) }
            }
        } else {
            sendByWatchConnectivity(data)
        }
    }

    fileprivate func sendByWatchConnectivity(_ data: Data) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessageData(data, replyHandler: nil, errorHandler: nil)
    }

    /// A message from the watch (through either link).
    func receive(_ data: Data) {
        guard let message = MirrorMessage.decode(data) else { return }
        switch message {
        case .command(let command):
            if let handlers { handlers.command(command) } else { send(.ended(runId: nil, saved: false)) }
        case .heartRate(let bpm, let date):
            if let handlers { handlers.heartRate(bpm, date) } else { send(.ended(runId: nil, saved: false)) }
        case .frame, .ended:
            break
        }
    }

    fileprivate func sessionEnded(_ session: HKWorkoutSession) {
        if session === mirroredSession { mirroredSession = nil }
    }
}

extension WatchMirrorService: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended || toState == .stopped else { return }
        Task { @MainActor in WatchMirrorService.shared.sessionEnded(workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in data.forEach(WatchMirrorService.shared.receive) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in WatchMirrorService.shared.sessionEnded(workoutSession) }
    }
}

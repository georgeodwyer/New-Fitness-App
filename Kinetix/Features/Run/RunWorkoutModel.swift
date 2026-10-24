import Foundation
import Observation
import SwiftData
import CoreLocation
import HealthKit
import TrainingEngine

/// Live state of a run: drives the engine from GPS (real or simulated) and a 1 s clock,
/// speaks announcements, and checkpoints the run.
@Observable
@MainActor
final class RunWorkoutModel {
    enum Phase { case ready, running, finished }

    struct Announcement: Identifiable {
        let id = UUID()
        let text: String
        let isCue: Bool
        let time: Double
    }

    let planned: PlannedSessionModel?
    let title: String
    let structure: RunStructure?
    let units: UnitSystem
    /// Simulated GPS playback speed (nil = real GPS).
    let simulationSpeed: Double?

    private(set) var phase: Phase = .ready
    private(set) var snapshot: RunSnapshot
    private(set) var announcements: [Announcement] = []
    private(set) var route: [RoutePoint] = []
    private(set) var authorization: CLAuthorizationStatus
    private(set) var hasGPSFix: Bool
    private(set) var log: RunLogModel?
    private(set) var finalSummary: RunSummary?
    /// The run is showing on the Apple Watch.
    private(set) var isMirroringToWatch = false
    /// The phone couldn't open Kinetix on the watch (asleep or locked): ask the runner to.
    private(set) var watchNeedsOpening = false
    /// Goes up each time End is pressed on the watch (the run screen then finishes the run).
    private(set) var watchEndRequests = 0
    /// End requests the screen has acted on (one can arrive while the trainer is minimised).
    @ObservationIgnored var handledWatchEndRequests = 0
    /// Where heart rate comes from during this run (set when it starts).
    private(set) var heartRateSource: RunHeartRateSource = .watch

    /// Quick toggle on the run screen (also respects Settings).
    var paceCuesEnabled: Bool {
        didSet {
            var config = engine.config
            config.paceCuesEnabled = paceCuesEnabled
            engine.updateConfig(config)
        }
    }

    @ObservationIgnored private var engine: RunEngine
    private let context: ModelContext
    private let voice = VoiceCoach()
    private let gps: GPSLocationSource?
    private let simulator: SimulatedLocationSource?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTick = Date()
    @ObservationIgnored private var lastCheckpoint = Date()
    // Simulation clock: simulated time advances `speed`× faster than real time.
    @ObservationIgnored private var clockOrigin = Date()
    @ObservationIgnored private var realOrigin = Date()
    @ObservationIgnored private let heartRateMonitor = HeartRateMonitor.shared
    @ObservationIgnored private var watchHeartRateQuery: HKQuery?
    private var lockScreen: WorkoutActivityController { .shared }
    @ObservationIgnored private var lastLockScreenKey: String?
    /// Identifies this run to the watch.
    @ObservationIgnored private let mirrorRunId = UUID()
    /// Wrist taps waiting to go out with the next frame.
    @ObservationIgnored private var pendingAlerts: [MirrorAlert] = []
    /// When the watch last sent live heart rate (Apple Health's slower readings are ignored meanwhile).
    @ObservationIgnored private var lastLiveWatchHeartRate: Date?

    private enum HeartRateOrigin { case strap, watchLive, health }

    /// The run built on the Record tab, if any.
    let custom: CustomRunWorkout?

    // MARK: Route

    /// Where the runner is on a planned route, for the run screen.
    struct RouteStatus: Equatable {
        var nextDirection: String?
        var distanceToNext: Double?
        var remainingMeters: Double
        var isOffRoute: Bool
        var isFinished: Bool
    }

    /// A route chosen on the Record tab to follow, with spoken directions.
    let plannedRoute: PlannedRoute?
    private(set) var routeStatus: RouteStatus?
    @ObservationIgnored private var guide: RouteGuide?

    init(planned: PlannedSessionModel?, custom: CustomRunWorkout? = nil, route: PlannedRoute? = nil, units: UnitSystem,
         settings: CoachingSettingsModel?, simulationSpeed: Double?, context: ModelContext) {
        self.planned = planned
        self.custom = custom
        self.plannedRoute = route.flatMap { $0.path.count > 1 ? $0 : nil }
        self.title = custom?.name ?? planned?.title ?? "Run"
        // A recorded run follows the runner's own workout even when it counts as a planned session.
        self.structure = custom.map(\.structure) ?? planned?.runStructure
        self.units = units
        self.simulationSpeed = simulationSpeed
        self.context = context

        let config = CoachingConfig(
            paceCueDelaySeconds: settings?.paceCueDelaySeconds ?? 20,
            toleranceSecondsPerKm: settings?.paceToleranceSecondsPerKm ?? 10,
            paceCuesEnabled: settings?.paceCuesEnabled ?? true,
            splitAnnouncementsEnabled: settings?.splitAnnouncementsEnabled ?? true,
            segmentAnnouncementsEnabled: settings?.segmentAnnouncementsEnabled ?? true,
            cuesDuringWarmUpCoolDown: settings?.cuesDuringWarmUpCoolDown ?? false,
            units: units
        )
        let engine = RunEngine(structure: structure, config: config)
        self.engine = engine
        self.snapshot = engine.snapshot()
        self.paceCuesEnabled = config.paceCuesEnabled

        let simulated = simulationSpeed != nil
        self.gps = simulated ? nil : GPSLocationSource()
        self.simulator = simulated ? SimulatedLocationSource(structure: structure, path: plannedRoute?.path ?? []) : nil
        self.authorization = simulated ? .authorizedWhenInUse : .notDetermined
        self.hasGPSFix = simulated

        if let plannedRoute {
            let guide = RouteGuide(route: plannedRoute, config: RouteGuide.Config(units: units))
            self.guide = guide
            self.routeStatus = Self.status(of: guide)
        }
        voice.voiceIdentifier = settings?.voiceIdentifier
        voice.volume = Float(settings?.cueVolume ?? 1)
        configureSources()
    }

    var isSimulated: Bool { simulationSpeed != nil }

    /// Pre-filled answer for "How hard was that run?".
    var typicalEffort: Double { custom?.type.typicalEffort ?? planned?.plannedEffort ?? 5 }

    /// Both a chest strap and the watch could give heart rate, so ask which to use.
    var shouldAskHeartRateSource: Bool {
        IntegrationSettings.shared.heartRateSensorID != nil && WatchMirrorService.shared.isAvailable
    }

    /// The paired strap's name, for the question.
    var strapName: String { IntegrationSettings.shared.heartRateSensorName ?? "Chest strap" }

    var needsPermission: Bool {
        !isSimulated && (authorization == .denied || authorization == .restricted)
    }

    // MARK: Lifecycle

    /// Call when the ready screen appears: asks for location permission and warms up GPS.
    func prepare() {
        // Wake the paired heart rate strap so it's connected by the time the run starts.
        heartRateMonitor.connectToSaved()
        guard let gps else { return }
        authorization = gps.authorizationStatus
        gps.requestPermission()
        gps.warmUp()
    }

    /// Starts the run. `heartRateSource` is the answer to "Heart rate from?" when it was asked.
    func start(heartRateSource chosen: RunHeartRateSource? = nil) {
        guard phase == .ready else { return }
        if let chosen { IntegrationSettings.shared.runHeartRateSource = chosen }
        heartRateSource = chosen ?? (IntegrationSettings.shared.heartRateSensorID != nil ? .strap : .watch)
        realOrigin = .now
        clockOrigin = .now
        let now = clockNow()
        voice.prepare()
        log = RunService.begin(planned: planned, title: title, simulated: isSimulated, recordType: custom?.type, in: context, now: now)
        phase = .running
        handle(engine.start(at: now))
        gps?.start()
        simulator?.start()
        startHeartRate(from: now)
        startMirroring()
        ActiveWorkout.shared.togglePause = { [weak self] in self?.togglePause() }
        lockScreen.start(title: title, kind: "run", state: .run(snapshot, units: units, now: .now))
        lastTick = now
        lastCheckpoint = now
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func togglePause() {
        let now = clockNow()
        if snapshot.isPaused {
            engine.resume(at: now)
            simulator?.start()
            voice.speak("Resumed.")
        } else {
            engine.pause(at: now)
            simulator?.stop()
            voice.speak("Paused.")
        }
        snapshot = engine.snapshot()
        updateLockScreen(important: true)
        publishToWatch()
    }

    func skipSegment() {
        handle(engine.skipSegment(at: clockNow()))
        snapshot = engine.snapshot()
        publishToWatch()
    }

    /// Marks a lap (from the watch's gestures or Lap button).
    func markLap() {
        let lap = engine.markLap(at: clockNow())
        snapshot = engine.snapshot()
        let text = Announcer.lap(lap, units: units)
        announcements.append(Announcement(text: text, isCue: false, time: snapshot.elapsedSeconds))
        if announcements.count > 20 { announcements.removeFirst() }
        voice.speak(text)
        publishToWatch()
    }

    /// Undoes the last skip or lap (the watch's "Undo").
    func undoLastControl() {
        guard engine.undoLastControl(at: clockNow()) else { return }
        snapshot = engine.snapshot()
        voice.speak(Announcer.undone)
        publishToWatch()
    }

    /// Stops tracking and returns the summary for the effort sheet.
    func stop() -> RunSummary {
        timer?.invalidate()
        timer = nil
        gps?.stop()
        simulator?.stop()
        voice.stop()
        stopHeartRate()
        lockScreen.end()
        ActiveWorkout.shared.togglePause = nil
        let summary = engine.summary()
        finalSummary = summary
        phase = .finished
        stopMirroring(saved: true)
        return summary
    }

    func save(effort: Double) {
        guard let log, let summary = finalSummary else { return }
        RunService.finish(summary, log: log, planned: planned, effort: effort, in: context)
    }

    func discard() {
        timer?.invalidate()
        gps?.stop()
        simulator?.stop()
        voice.stop()
        stopHeartRate()
        lockScreen.end()
        ActiveWorkout.shared.togglePause = nil
        stopMirroring(saved: false)
        if let log { RunService.discard(log, in: context) }
    }

    /// Leaves the screen keeping what was recorded (as an unfinished run).
    func abandonKeepingData() {
        _ = stop()
        if let log, let summary = finalSummary { RunService.checkpoint(summary, into: log, in: context) }
    }

    // MARK: Internals

    /// Throttled lock-screen update; a new step or pace status goes out straight away.
    private func updateLockScreen(important: Bool = false) {
        let key = "\(snapshot.segmentIndex ?? -1)-\(String(describing: snapshot.paceStatus))-\(snapshot.isPaused)"
        let changed = key != lastLockScreenKey
        lastLockScreenKey = key
        lockScreen.update(.run(snapshot, units: units, now: .now), important: important || changed)
    }

    /// Heart rate from the chosen source: a Bluetooth strap, or the Apple Watch (live from
    /// the mirrored run, or through Apple Health when the watch is recording a workout).
    private func startHeartRate(from start: Date) {
        if heartRateSource == .strap {
            heartRateMonitor.onHeartRate = { [weak self] bpm, _ in self?.receiveHeartRate(bpm, from: .strap) }
        } else {
            // The watch was chosen: let the strap go (saves its battery).
            heartRateMonitor.disconnect()
        }
        if IntegrationSettings.shared.useWatchHeartRate {
            watchHeartRateQuery = HealthService.shared.startLiveHeartRate(from: Date.now.addingTimeInterval(-60)) { [weak self] bpm, _ in
                self?.receiveHeartRate(bpm, from: .health)
            }
        }
    }

    private func stopHeartRate() {
        heartRateMonitor.onHeartRate = nil
        heartRateMonitor.disconnect()
        HealthService.shared.stop(watchHeartRateQuery)
        watchHeartRateQuery = nil
    }

    private func receiveHeartRate(_ bpm: Double, from origin: HeartRateOrigin) {
        guard phase == .running else { return }
        let strapInUse = heartRateSource == .strap && heartRateMonitor.isConnected
        switch origin {
        case .strap:
            guard heartRateSource == .strap else { return }
        case .watchLive:
            // A strap that was chosen and is connected wins.
            guard !strapInUse else { return }
            lastLiveWatchHeartRate = .now
        case .health:
            // Apple Health's readings are slower: only used when nothing better is coming in.
            guard !strapInUse else { return }
            if let last = lastLiveWatchHeartRate, Date.now.timeIntervalSince(last) < 15 { return }
        }
        engine.addHeartRate(bpm, at: clockNow())
        snapshot = engine.snapshot()
    }

    // MARK: Apple Watch

    private func startMirroring() {
        let handlers = WatchMirrorService.Handlers(
            command: { [weak self] command in self?.handleWatch(command) },
            heartRate: { [weak self] bpm, _ in self?.receiveHeartRate(bpm, from: .watchLive) },
            watchStatus: { [weak self] showing in self?.watchNeedsOpening = !showing }
        )
        isMirroringToWatch = WatchMirrorService.shared.begin(runId: mirrorRunId, handlers: handlers)
        publishToWatch()
    }

    private func stopMirroring(saved: Bool) {
        guard isMirroringToWatch else { return }
        isMirroringToWatch = false
        watchNeedsOpening = false
        WatchMirrorService.shared.end(saved: saved)
    }

    /// Sends the run screen (and any wrist taps) to the watch.
    private func publishToWatch() {
        guard isMirroringToWatch, phase == .running else { return }
        let frame = MirrorFrame(runId: mirrorRunId, title: title, units: units, isStructured: structure != nil,
                                snapshot: snapshot, alerts: pendingAlerts, sentAt: .now)
        pendingAlerts = []
        WatchMirrorService.shared.publish(frame)
    }

    private func handleWatch(_ command: MirrorCommand) {
        guard phase == .running else { return }
        switch command {
        case .pause: if !snapshot.isPaused { togglePause() }
        case .resume: if snapshot.isPaused { togglePause() }
        case .skipStep: skipSegment()
        case .lap: markLap()
        case .undo: undoLastControl()
        case .end: watchEndRequests += 1
        }
    }

    private func configureSources() {
        gps?.onSample = { [weak self] sample in self?.receive(sample) }
        gps?.onAuthorizationChange = { [weak self] status in self?.authorization = status }
        simulator?.onSample = { [weak self] sample in self?.receive(sample) }
    }

    private func clockNow() -> Date {
        guard let speed = simulationSpeed else { return .now }
        return clockOrigin.addingTimeInterval(Date.now.timeIntervalSince(realOrigin) * speed)
    }

    private func receive(_ sample: LocationSample) {
        if sample.horizontalAccuracy >= 0 && sample.horizontalAccuracy <= 30 { hasGPSFix = true }
        guard phase == .running else { return }
        handle(engine.addLocation(sample))
        snapshot = engine.snapshot()
        // Something happened (new step, cue, split): tell the watch now rather than on the next tick.
        if !pendingAlerts.isEmpty { publishToWatch() }
        if !snapshot.isPaused, route.last.map({ $0.latitude != sample.latitude }) ?? true {
            route.append(RoutePoint(latitude: sample.latitude, longitude: sample.longitude, elapsed: snapshot.elapsedSeconds))
        }
        followRoute(sample)
    }

    private func followRoute(_ sample: LocationSample) {
        guard var guide, !snapshot.isPaused, sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= 50 else { return }
        let events = guide.update(latitude: sample.latitude, longitude: sample.longitude)
        self.guide = guide
        let status = Self.status(of: guide)
        if status != routeStatus { routeStatus = status }
        for event in events {
            let text = event.announcement(units: units)
            announcements.append(Announcement(text: text, isCue: event == .offRoute, time: snapshot.elapsedSeconds))
            if announcements.count > 20 { announcements.removeFirst() }
            voice.speak(text)
        }
    }

    private static func status(of guide: RouteGuide) -> RouteStatus {
        RouteStatus(nextDirection: guide.nextInstruction?.text,
                    distanceToNext: guide.distanceToNext.map { ($0 / 10).rounded() * 10 },
                    remainingMeters: (guide.remainingMeters / 10).rounded() * 10,
                    isOffRoute: guide.isOffRoute, isFinished: guide.isFinished)
    }

    private func tick() {
        guard phase == .running else { return }
        let now = clockNow()
        if let simulator, !snapshot.isPaused {
            simulator.advance(by: now.timeIntervalSince(lastTick), clockNow: now)
        }
        lastTick = now
        handle(engine.tick(at: now))
        snapshot = engine.snapshot()
        updateLockScreen()
        publishToWatch()
        if now.timeIntervalSince(lastCheckpoint) >= 30, let log {
            lastCheckpoint = now
            RunService.checkpoint(engine.summary(), into: log, in: context)
        }
    }

    private func handle(_ events: [RunEvent]) {
        for event in events {
            let isCue: Bool
            if case .paceCue = event { isCue = true } else { isCue = false }
            announcements.append(Announcement(text: event.announcement, isCue: isCue, time: snapshot.elapsedSeconds))
            if announcements.count > 20 { announcements.removeFirst() }
            voice.speak(event.announcement)
            if isMirroringToWatch { pendingAlerts.append(MirrorAlert(event: event)) }
        }
    }
}

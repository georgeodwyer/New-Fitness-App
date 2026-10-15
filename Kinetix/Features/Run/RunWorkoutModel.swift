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

    func start() {
        guard phase == .ready else { return }
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
    }

    func skipSegment() {
        handle(engine.skipSegment(at: clockNow()))
        snapshot = engine.snapshot()
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

    /// Heart rate from a Bluetooth strap (preferred: it updates every second) and/or an
    /// Apple Watch through Apple Health.
    private func startHeartRate(from start: Date) {
        heartRateMonitor.onHeartRate = { [weak self] bpm, _ in self?.receiveHeartRate(bpm, fromStrap: true) }
        if IntegrationSettings.shared.useWatchHeartRate {
            watchHeartRateQuery = HealthService.shared.startLiveHeartRate(from: Date.now.addingTimeInterval(-60)) { [weak self] bpm, _ in
                self?.receiveHeartRate(bpm, fromStrap: false)
            }
        }
    }

    private func stopHeartRate() {
        heartRateMonitor.onHeartRate = nil
        heartRateMonitor.disconnect()
        HealthService.shared.stop(watchHeartRateQuery)
        watchHeartRateQuery = nil
    }

    private func receiveHeartRate(_ bpm: Double, fromStrap: Bool) {
        guard phase == .running else { return }
        // When a strap is connected, ignore the Watch's slower readings.
        if !fromStrap && heartRateMonitor.isConnected { return }
        engine.addHeartRate(bpm, at: clockNow())
        snapshot = engine.snapshot()
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
        }
    }
}

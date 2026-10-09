import Foundation
import Observation
import SwiftData
import CoreLocation
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

    init(planned: PlannedSessionModel?, units: UnitSystem, settings: CoachingSettingsModel?, simulationSpeed: Double?, context: ModelContext) {
        self.planned = planned
        self.title = planned?.title ?? "Run"
        self.structure = planned?.runStructure
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
        self.simulator = simulated ? SimulatedLocationSource(structure: structure) : nil
        self.authorization = simulated ? .authorizedWhenInUse : .notDetermined
        self.hasGPSFix = simulated

        voice.voiceIdentifier = settings?.voiceIdentifier
        voice.volume = Float(settings?.cueVolume ?? 1)
        configureSources()
    }

    var isSimulated: Bool { simulationSpeed != nil }

    var needsPermission: Bool {
        !isSimulated && (authorization == .denied || authorization == .restricted)
    }

    // MARK: Lifecycle

    /// Call when the ready screen appears: asks for location permission and warms up GPS.
    func prepare() {
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
        log = RunService.begin(planned: planned, title: title, simulated: isSimulated, in: context, now: now)
        phase = .running
        handle(engine.start(at: now))
        gps?.start()
        simulator?.start()
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
        if let log { RunService.discard(log, in: context) }
    }

    /// Leaves the screen keeping what was recorded (as an unfinished run).
    func abandonKeepingData() {
        _ = stop()
        if let log, let summary = finalSummary { RunService.checkpoint(summary, into: log, in: context) }
    }

    // MARK: Internals

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

import Foundation
import Observation
import HealthKit
import CoreLocation
import WatchKit
import AVFoundation
import TrainingEngine

/// Runs a workout on the watch on its own: an Apple Health workout session (keeps the app
/// running with the screen down, records heart rate and saves the workout), GPS from the
/// watch, and the same run engine as the iPhone for pace targets, steps and cues, which
/// arrive as wrist taps and, through AirPods or the speaker, spoken prompts.
///
/// It can also mirror a run recorded on the iPhone: the phone opens the watch app, which
/// starts a workout session (to stay awake and read heart rate) and shows the phone's run
/// screen, tapping the wrist when the phone says to. Buttons and heart rate go back to the
/// phone, which saves the run, so the watch throws its own copy of the workout away.
@Observable
@MainActor
final class RunWorkoutManager: NSObject {
    enum Phase: Equatable { case idle, starting, running, finished }
    enum Mode: Equatable { case standalone, mirroring }

    static let shared = RunWorkoutManager()

    private(set) var phase: Phase = .idle
    private(set) var snapshot: RunSnapshot?
    private(set) var summary: RunSummary?
    private(set) var option: WatchRunOption?
    private(set) var startedAt: Date?
    private(set) var finishedAt: Date?
    private(set) var lastMessage: String?
    private(set) var errorText: String?
    var voiceEnabled = true
    private(set) var mode: Mode = .standalone
    /// No word from the phone for a while during a mirrored run.
    private(set) var isPhoneLinkStale = false
    /// Shown on the run list after a mirrored run, e.g. "Run finished on your iPhone".
    private(set) var notice: String?
    private(set) var mirrorIsStructured = false
    private(set) var mirrorUnits: UnitSystem?
    @ObservationIgnored private var mirrorRunId: UUID?
    @ObservationIgnored private var lastFrameAt: Date?
    /// Phone runs that have finished, so a late frame doesn't bring one back.
    @ObservationIgnored private var endedMirrorRuns: Set<UUID> = []

    @ObservationIgnored private var engine: RunEngine?
    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var routeBuilder: HKWorkoutRouteBuilder?
    @ObservationIgnored private var routePoints = 0
    @ObservationIgnored private var workoutId: UUID?
    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let speech = AVSpeechSynthesizer()

    var units: UnitSystem { mirrorUnits ?? WatchStore.shared.plan.units }
    var isPaused: Bool { snapshot?.isPaused ?? false }
    var isMirroring: Bool { mode == .mirroring }
    /// The run has steps (so the rep page is shown).
    var isStructured: Bool { isMirroring ? mirrorIsStructured : option?.structure != nil }

    // MARK: Permission

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.distanceWalkingRunning),
                                       HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType()]
        try? await healthStore.requestAuthorization(toShare: share, read: read)
        if locationManager.authorizationStatus == .notDetermined { locationManager.requestWhenInUseAuthorization() }
    }

    // MARK: Lifecycle

    func start(_ option: WatchRunOption) async {
        guard phase == .idle || phase == .finished else { return }
        reset()
        phase = .starting
        self.option = option
        await requestAuthorization()

        let plan = WatchStore.shared.plan
        var coaching = plan.coaching
        coaching.units = plan.units
        var engine = RunEngine(structure: option.structure, config: coaching)

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)

            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            startedAt = start
            let events = engine.start(at: start)
            self.engine = engine
            handle(events)
        } catch {
            errorText = "Couldn't start the workout: \(error.localizedDescription)"
            phase = .idle
            return
        }

        startLocation()
        configureSpeech()
        phase = .running
        WKInterfaceDevice.current().play(.start)
        snapshot = self.engine?.snapshot()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func togglePause() {
        if isMirroring {
            guard phase == .running, snapshot != nil else { return }
            sendToPhone(.command(isPaused ? .resume : .pause))
            // Show it straight away; the phone's next frame confirms it.
            snapshot?.isPaused.toggle()
            WKInterfaceDevice.current().play(isPaused ? .stop : .start)
            return
        }
        guard phase == .running, var engine else { return }
        let now = Date()
        if engine.snapshot().isPaused {
            engine.resume(at: now)
            session?.resume()
            WKInterfaceDevice.current().play(.start)
        } else {
            engine.pause(at: now)
            session?.pause()
            WKInterfaceDevice.current().play(.stop)
        }
        self.engine = engine
        snapshot = engine.snapshot()
    }

    func skipStep() {
        if isMirroring {
            sendToPhone(.command(.skipStep))
            return
        }
        guard phase == .running, var engine else { return }
        let events = engine.skipSegment(at: Date())
        self.engine = engine
        handle(events)
        snapshot = engine.snapshot()
    }

    /// Stops recording and saves the workout to Apple Health; then the summary shows.
    func end() async {
        if isMirroring {
            await endMirroredRun()
            return
        }
        guard phase == .running, let engine else { return }
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        speech.stopSpeaking(at: .immediate)
        let end = Date()
        finishedAt = end
        summary = engine.summary()
        session?.end()
        if let builder {
            try? await builder.endCollection(at: end)
            if let workout = try? await builder.finishWorkout() {
                workoutId = workout.uuid
                if routePoints > 1, let routeBuilder {
                    _ = try? await routeBuilder.finishRoute(with: workout, metadata: nil)
                }
            }
        }
        WKInterfaceDevice.current().play(.success)
        phase = .finished
    }

    /// Sends the run to the phone with the effort rating, then goes back to the list.
    func save(effort: Double) {
        guard let option, let summary, let startedAt else { return }
        let result = WatchRunResult(option: option, startedAt: startedAt, finishedAt: finishedAt ?? Date(), summary: summary,
                                    effort: effort, healthKitWorkoutId: workoutId)
        WatchStore.shared.send(result.thinned())
        reset()
    }

    /// Throws the run away (also removes it from Apple Health if it was saved).
    func discard() {
        if let workoutId {
            let predicate = HKQuery.predicateForObject(with: workoutId)
            healthStore.deleteObjects(of: HKObjectType.workoutType(), predicate: predicate) { _, _, _ in }
        }
        if phase == .running {
            timer?.invalidate()
            locationManager.stopUpdatingLocation()
            session?.end()
            builder?.discardWorkout()
        }
        reset()
    }

    private func reset() {
        timer?.invalidate()
        timer = nil
        engine = nil
        session = nil
        builder = nil
        routeBuilder = nil
        routePoints = 0
        workoutId = nil
        snapshot = nil
        summary = nil
        option = nil
        mode = .standalone
        isPhoneLinkStale = false
        notice = nil
        mirrorIsStructured = false
        mirrorUnits = nil
        mirrorRunId = nil
        lastFrameAt = nil
        startedAt = nil
        finishedAt = nil
        lastMessage = nil
        errorText = nil
        phase = .idle
    }

    // MARK: Engine

    private func tick() {
        guard phase == .running, var engine else { return }
        let events = engine.tick(at: Date())
        self.engine = engine
        handle(events)
        snapshot = engine.snapshot()
    }

    private func receive(_ samples: [LocationSample]) {
        guard phase == .running, var engine else { return }
        var events: [RunEvent] = []
        for sample in samples { events += engine.addLocation(sample) }
        self.engine = engine
        handle(events)
        snapshot = engine.snapshot()
    }

    private func receiveHeartRate(_ bpm: Double, at date: Date) {
        if isMirroring {
            guard phase == .running else { return }
            sendToPhone(.heartRate(bpm: bpm, at: date))
            return
        }
        guard phase == .running, var engine else { return }
        engine.addHeartRate(bpm, at: date)
        self.engine = engine
    }

    private func handle(_ events: [RunEvent]) {
        for event in events {
            lastMessage = event.announcement
            let device = WKInterfaceDevice.current()
            switch event {
            case .paceCue(let cue):
                // Up = speed up, down = ease off.
                device.play(cue.direction == .tooSlow ? .directionUp : .directionDown)
            case .segmentStarted:
                device.play(.notification)
            case .split:
                device.play(.click)
            case .workoutComplete:
                device.play(.success)
            }
            if voiceEnabled { speak(event.announcement) }
        }
    }

    // MARK: Mirroring a run from the iPhone

    /// The phone has opened the app for a run it's recording.
    func startMirroring(configuration: HKWorkoutConfiguration) async {
        // A finished watch run still on its summary screen is saved (with its usual effort) so
        // it isn't lost, then the phone's run takes over.
        if phase == .finished { save(effort: option?.typicalEffort ?? 5) }
        // A run already going on the watch carries on; the phone's run just isn't shown.
        guard phase == .idle else { return }
        reset()
        mode = .mirroring
        phase = .running
        option = WatchRunOption(id: UUID(), source: .free, title: "Run on iPhone")
        let start = Date()
        startedAt = start
        lastFrameAt = start
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.mirrorTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        await requestAuthorization()
        guard isMirroring else { return }
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            // The direct link to the phone. If it fails, messages go through WatchConnectivity.
            session.startMirroringToCompanionDevice { _, _ in }
        } catch {
            // Without a workout session there's no live heart rate, but the run still shows.
        }
        WKInterfaceDevice.current().play(.start)
    }

    /// A message from the phone (through either link).
    func receiveFromPhone(_ data: Data) {
        guard let message = MirrorMessage.decode(data) else { return }
        switch message {
        case .frame(let frame):
            receive(frame)
        case .ended(let runId, let saved):
            if let runId { endedMirrorRuns.insert(runId) }
            guard isMirroring, runId == nil || runId == mirrorRunId || mirrorRunId == nil else { return }
            Task { await finishMirroring(notice: saved ? "Run finished on your iPhone." : "Run discarded on your iPhone.") }
        case .command, .heartRate:
            break
        }
    }

    private func receive(_ frame: MirrorFrame) {
        guard !endedMirrorRuns.contains(frame.runId) else { return }
        guard isMirroring else {
            // The phone is recording and the app is open but wasn't woken for it: join in.
            guard phase == .idle || phase == .finished, frame.isFresh(at: Date()) else { return }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .running
            configuration.locationType = .outdoor
            Task { await startMirroring(configuration: configuration) }
            return
        }
        mirrorRunId = frame.runId
        lastFrameAt = Date()
        isPhoneLinkStale = false
        snapshot = frame.snapshot
        mirrorIsStructured = frame.isStructured
        mirrorUnits = frame.units
        if option?.title != frame.title {
            option = WatchRunOption(id: frame.runId, source: .free, title: frame.title)
        }
        let device = WKInterfaceDevice.current()
        for alert in frame.alerts {
            switch alert {
            case .speedUp: device.play(.directionUp)
            case .easeOff: device.play(.directionDown)
            case .newStep: device.play(.notification)
            case .split: device.play(.click)
            case .complete: device.play(.success)
            }
        }
    }

    private func mirrorTick() {
        guard isMirroring, let lastFrameAt else { return }
        let silence = Date().timeIntervalSince(lastFrameAt)
        isPhoneLinkStale = silence > 15
        // The phone has gone quiet for a long time (its app was closed): stop showing the run.
        if silence > 600 {
            Task { await finishMirroring(notice: "Lost touch with your iPhone. Check the run there.") }
        }
    }

    /// End pressed on the watch: the phone finishes the run and asks how hard it was.
    private func endMirroredRun() async {
        guard isMirroring else { return }
        if isPhoneLinkStale {
            await finishMirroring(notice: "Stopped showing the run. Your iPhone may still be recording it.")
            return
        }
        sendToPhone(.command(.end))
        // The phone answers with "ended"; if it doesn't, stop anyway.
        let runId = mirrorRunId
        try? await Task.sleep(for: .seconds(8))
        if isMirroring, mirrorRunId == runId {
            await finishMirroring(notice: "Stopped showing the run. Finish it on your iPhone.")
        }
    }

    /// Stops the watch's side of a mirrored run. The phone saves the run, so the watch's own
    /// copy of the workout is thrown away (no duplicate in Apple Health).
    private func finishMirroring(notice: String) async {
        guard isMirroring else { return }
        if let mirrorRunId { endedMirrorRuns.insert(mirrorRunId) }
        timer?.invalidate()
        timer = nil
        session?.end()
        builder?.discardWorkout()
        reset()
        self.notice = notice
        WKInterfaceDevice.current().play(.success)
    }

    func clearNotice() { notice = nil }

    private func sendToPhone(_ message: MirrorMessage) {
        let data = message.encoded()
        guard let session else {
            WatchStore.shared.sendMessage(data)
            return
        }
        session.sendToRemoteWorkoutSession(data: data) { success, _ in
            guard !success else { return }
            Task { @MainActor in WatchStore.shared.sendMessage(data) }
        }
    }

    // MARK: Voice

    private func configureSpeech() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt)
    }

    private func speak(_ text: String) {
        guard !text.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        speech.speak(utterance)
    }

    // MARK: Location

    private func startLocation() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.distanceFilter = kCLDistanceFilterNone
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        if modes.contains("location") { locationManager.allowsBackgroundLocationUpdates = true }
        locationManager.startUpdatingLocation()
    }

    fileprivate func addRoute(_ locations: [CLLocation]) {
        guard let routeBuilder, !locations.isEmpty, !isPaused else { return }
        routePoints += locations.count
        routeBuilder.insertRouteData(locations) { _, _ in }
    }
}

// MARK: - Delegates

extension RunWorkoutManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let usable = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }
        let samples = usable.map {
            LocationSample(timestamp: $0.timestamp, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                           horizontalAccuracy: $0.horizontalAccuracy, speed: $0.speed)
        }
        Task { @MainActor in
            self.addRoute(usable)
            self.receive(samples)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension RunWorkoutManager: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.errorText = message }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in data.forEach(self.receiveFromPhone) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        // Messages carry on through WatchConnectivity.
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRate = HKQuantityType(.heartRate)
        guard collectedTypes.contains(heartRate),
              let quantity = workoutBuilder.statistics(for: heartRate)?.mostRecentQuantity() else { return }
        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        Task { @MainActor in self.receiveHeartRate(bpm, at: Date()) }
    }
}

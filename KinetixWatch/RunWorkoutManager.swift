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
@Observable
@MainActor
final class RunWorkoutManager: NSObject {
    enum Phase: Equatable { case idle, starting, running, finished }

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

    var units: UnitSystem { WatchStore.shared.plan.units }
    var isPaused: Bool { snapshot?.isPaused ?? false }

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
        guard phase == .running, var engine else { return }
        let events = engine.skipSegment(at: Date())
        self.engine = engine
        handle(events)
        snapshot = engine.snapshot()
    }

    /// Stops recording and saves the workout to Apple Health; then the summary shows.
    func end() async {
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

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRate = HKQuantityType(.heartRate)
        guard collectedTypes.contains(heartRate),
              let quantity = workoutBuilder.statistics(for: heartRate)?.mostRecentQuantity() else { return }
        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        Task { @MainActor in self.receiveHeartRate(bpm, at: Date()) }
    }
}

import XCTest
@testable import TrainingEngine

final class RunEngineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let target = PaceRange(fastest: Pace(secondsPerKm: 280), slowest: Pace(secondsPerKm: 290))

    /// Feeds samples (and a clock tick per sample) and collects all events with their times.
    private func run(_ engine: inout RunEngine, _ samples: [LocationSample]) -> [(Double, RunEvent)] {
        var events: [(Double, RunEvent)] = engine.start(at: start).map { (0, $0) }
        for sample in samples {
            let t = sample.timestamp.timeIntervalSince(start)
            events += engine.addLocation(sample).map { (t, $0) }
            events += engine.tick(at: sample.timestamp).map { (t, $0) }
        }
        return events
    }

    private func cues(_ events: [(Double, RunEvent)]) -> [(Double, PaceCue)] {
        events.compactMap { time, event in
            if case .paceCue(let cue) = event { return (time, cue) }
            return nil
        }
    }

    private func steady(_ meters: Double, target: PaceRange? = nil) -> RunStructure {
        RunStructure(segments: [RunSegment(kind: .steady, length: .distance(meters: meters), targetPace: target ?? self.target, label: "Tempo")])
    }

    // MARK: Distance, smoothing, splits

    func testDistanceAccurateWithRealisticGPSNoise() {
        let structure = steady(5000)
        let runner = SimulatedRunner(structure: structure)
        var engine = RunEngine(structure: structure)
        _ = run(&engine, runner.samples(start: start, duration: 5000 * 0.285))
        // True distance ≈ 5000 m; drifting GPS adds a little.
        XCTAssertEqual(engine.summary().distanceMeters, 5000, accuracy: 100)
    }

    func testJitterDoesNotTriggerCuesWhenOnPace() {
        let structure = steady(5000)
        let runner = SimulatedRunner(structure: structure, speedNoise: 0.4, seed: 7)
        var engine = RunEngine(structure: structure)
        let events = run(&engine, runner.samples(start: start, duration: 1200))
        XCTAssertTrue(cues(events).isEmpty, "Noisy but on-pace running must not trigger cues")
        let summary = engine.summary()
        XCTAssertGreaterThan(summary.timeInTargetFraction ?? 0, 0.85)
    }

    func testSplitsEveryKilometre() {
        let structure = steady(3200)
        let runner = SimulatedRunner(structure: structure, driftMeters: 0, speedNoise: 0)
        var engine = RunEngine(structure: structure)
        let events = run(&engine, runner.samples(start: start, duration: 3200 * 0.285))
        let splits = events.compactMap { _, event -> Split? in
            if case .split(let split, _) = event { return split }
            return nil
        }
        XCTAssertEqual(splits.map(\.index), [1, 2, 3])
        for split in splits {
            XCTAssertEqual(split.durationSeconds, 285, accuracy: 3)
        }
        XCTAssertTrue(events.contains { if case .split(_, let text) = $0.1 { return text.hasPrefix("Kilometre 1.") }; return false })
    }

    func testSplitsInMiles() {
        let structure = steady(3500)
        let runner = SimulatedRunner(structure: structure, driftMeters: 0, speedNoise: 0)
        var engine = RunEngine(structure: structure, config: CoachingConfig(units: .imperial))
        let events = run(&engine, runner.samples(start: start, duration: 3500 * 0.285))
        let texts = events.map(\.1.announcement)
        XCTAssertTrue(texts.contains { $0.hasPrefix("Mile 2.") && $0.contains("per mile") })
    }

    // MARK: Pace cues

    func testTooFastTriggersCueAfterDelayThenRepeatsAfterAnotherFullDelay() {
        let structure = steady(6000)
        // 15% too fast from 60 s to 130 s.
        let runner = SimulatedRunner(structure: structure, deviations: [.init(segmentIndex: 0, from: 60, to: 130, speedFactor: 1.15)],
                                     driftMeters: 0, speedNoise: 0)
        var engine = RunEngine(structure: structure)
        let found = cues(run(&engine, runner.samples(start: start, duration: 200)))
        XCTAssertEqual(found.count, 2, "\(found.map(\.0))")
        XCTAssertTrue(found.allSatisfy { $0.1.direction == .tooFast })
        XCTAssertTrue(found[0].1.message.hasPrefix("Ease off, you're running too fast"))
        XCTAssertTrue(found[0].1.message.contains("4:40 to 4:50 per kilometre"))
        // Smoothed pace takes a few seconds to cross the threshold, then 20 s must pass.
        XCTAssertGreaterThanOrEqual(found[0].0, 80)
        XCTAssertLessThan(found[0].0, 95)
        XCTAssertEqual(found[1].0 - found[0].0, 20, accuracy: 1.5)
    }

    func testTooSlowCue() {
        let structure = steady(6000)
        let runner = SimulatedRunner(structure: structure, deviations: [.init(segmentIndex: 0, from: 30, to: 90, speedFactor: 0.85)],
                                     driftMeters: 0, speedNoise: 0)
        var engine = RunEngine(structure: structure)
        let found = cues(run(&engine, runner.samples(start: start, duration: 100)))
        XCTAssertFalse(found.isEmpty)
        XCTAssertTrue(found[0].1.message.hasPrefix("Pick it up, you're running too slow"))
    }

    func testShortExcursionDoesNotCue() {
        let structure = steady(6000)
        let runner = SimulatedRunner(structure: structure, deviations: [.init(segmentIndex: 0, from: 60, to: 72, speedFactor: 1.2)],
                                     driftMeters: 0, speedNoise: 0)
        var engine = RunEngine(structure: structure)
        XCTAssertTrue(cues(run(&engine, runner.samples(start: start, duration: 200))).isEmpty)
    }

    func testCueDelayIsConfigurable() {
        let structure = steady(6000)
        let runner = SimulatedRunner(structure: structure, deviations: [.init(segmentIndex: 0, from: 60, to: 200, speedFactor: 1.15)],
                                     driftMeters: 0, speedNoise: 0)
        var engine = RunEngine(structure: structure, config: CoachingConfig(paceCueDelaySeconds: 45))
        let found = cues(run(&engine, runner.samples(start: start, duration: 200)))
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[1].0 - found[0].0, 45, accuracy: 1.5)
    }

    func testToleranceWidensTarget() {
        let structure = steady(6000)
        // 5% fast ≈ 13-14 s/km faster than the fast end of 4:40.
        let runner = SimulatedRunner(structure: structure, deviations: [.init(segmentIndex: 0, from: 30, to: 200, speedFactor: 1.05)],
                                     driftMeters: 0, speedNoise: 0)
        var strict = RunEngine(structure: structure, config: CoachingConfig(toleranceSecondsPerKm: 5))
        var relaxed = RunEngine(structure: structure, config: CoachingConfig(toleranceSecondsPerKm: 20))
        XCTAssertFalse(cues(run(&strict, runner.samples(start: start, duration: 150))).isEmpty)
        XCTAssertTrue(cues(run(&relaxed, runner.samples(start: start, duration: 150))).isEmpty)
    }

    func testNoCuesInWarmUpUnlessEnabled() {
        let structure = RunStructure(segments: [
            RunSegment(kind: .warmUp, length: .duration(seconds: 300), targetPace: PaceRange(fastest: Pace(secondsPerKm: 330), slowest: Pace(secondsPerKm: 360)))
        ])
        let runner = SimulatedRunner(structure: structure, deviations: [.init(segmentIndex: 0, from: 0, to: 300, speedFactor: 1.3)],
                                     driftMeters: 0, speedNoise: 0)
        var quiet = RunEngine(structure: structure)
        XCTAssertTrue(cues(run(&quiet, runner.samples(start: start, duration: 200))).isEmpty)
        var chatty = RunEngine(structure: structure, config: CoachingConfig(cuesDuringWarmUpCoolDown: true))
        XCTAssertFalse(cues(run(&chatty, runner.samples(start: start, duration: 200))).isEmpty)
    }

    func testCuesCanBeTurnedOff() {
        let structure = steady(6000)
        let runner = SimulatedRunner(structure: structure, deviations: [.init(segmentIndex: 0, from: 30, to: 200, speedFactor: 1.2)],
                                     driftMeters: 0, speedNoise: 0)
        var engine = RunEngine(structure: structure, config: CoachingConfig(paceCuesEnabled: false))
        XCTAssertTrue(cues(run(&engine, runner.samples(start: start, duration: 150))).isEmpty)
    }

    // MARK: Segments

    func testStructuredIntervalSessionAnnouncesSegments() {
        let zones = PaceZones(race: RaceResult(distanceMeters: 5000, timeSeconds: 1320))
        let template = TestSupport.templates.workouts(type: .intervals, level: .intermediate)[1] // 5 × 800 m
        let structure = RunBuilder.structure(from: template, zones: zones)
        let runner = SimulatedRunner(structure: structure, driftMeters: 1, speedNoise: 0.1)
        var engine = RunEngine(structure: structure)
        let events = run(&engine, runner.samples(start: start, duration: 3600))

        let started = events.compactMap { _, event -> Int? in
            if case .segmentStarted(let index, _, _) = event { return index }
            return nil
        }
        XCTAssertEqual(started, Array(0..<structure.segments.count), "Every segment is announced once, in order")
        XCTAssertTrue(events.contains { if case .workoutComplete = $0.1 { return true }; return false })
        let texts = events.map(\.1.announcement)
        XCTAssertTrue(texts.first?.hasPrefix("Warm-up. 15 minutes easy") ?? false)
        XCTAssertTrue(texts.contains { $0.hasPrefix("Rep 1 of 5. 800 metres at") })
        XCTAssertTrue(texts.contains { $0.hasPrefix("Recovery jog. 2 minutes") })
        XCTAssertTrue(cues(events).isEmpty, "Following target paces produces no cues")

        let summary = engine.summary()
        XCTAssertEqual(summary.segments.count, structure.segments.count)
        let reps = summary.segments.filter { $0.segment.kind == .work }
        XCTAssertEqual(reps.count, 5)
        for rep in reps {
            XCTAssertEqual(rep.distanceMeters, 800, accuracy: 5)
        }
    }

    func testDemoRunnerTriggersCues() {
        let zones = PaceZones(race: RaceResult(distanceMeters: 5000, timeSeconds: 1320))
        let template = TestSupport.templates.workouts(type: .tempo, level: .intermediate)[2] // 20 min tempo
        let structure = RunBuilder.structure(from: template, zones: zones)
        var engine = RunEngine(structure: structure)
        let found = cues(run(&engine, SimulatedRunner.demo(structure: structure).samples(start: start, duration: 3000)))
        XCTAssertTrue(found.contains { $0.1.direction == .tooFast })
        XCTAssertTrue(found.contains { $0.1.direction == .tooSlow })
    }

    func testSkipSegment() {
        let structure = RunStructure(segments: [
            RunSegment(kind: .warmUp, length: .duration(seconds: 600)),
            RunSegment(kind: .work, length: .distance(meters: 1000), targetPace: target, label: "Main set")
        ])
        var engine = RunEngine(structure: structure)
        _ = engine.start(at: start)
        let events = engine.skipSegment(at: start.addingTimeInterval(30))
        XCTAssertEqual(engine.snapshot().segmentIndex, 1)
        XCTAssertTrue(events.first?.announcement.hasPrefix("Main set. 1 kilometre at 4:40 to 4:50 per kilometre") ?? false)
    }

    func testPauseExcludesTimeAndDistance() {
        let structure = steady(5000)
        let runner = SimulatedRunner(structure: structure, driftMeters: 0, speedNoise: 0)
        let samples = runner.samples(start: start, duration: 300)
        var engine = RunEngine(structure: structure)
        _ = engine.start(at: start)
        for sample in samples.prefix(101) { _ = engine.addLocation(sample) } // 0...100 s
        engine.pause(at: start.addingTimeInterval(100))
        // While paused the runner keeps moving (e.g. walking to a crossing): ignored.
        for sample in samples[101...200] { _ = engine.addLocation(sample) }
        engine.resume(at: start.addingTimeInterval(200))
        for sample in samples[201...] { _ = engine.addLocation(sample) }
        let summary = engine.summary()
        XCTAssertEqual(summary.durationSeconds, 200, accuracy: 1.5)
        XCTAssertEqual(summary.distanceMeters, 200 * 1000 / 285.0, accuracy: 20)
    }

    func testBadFixesIgnored() {
        var engine = RunEngine(structure: steady(5000))
        _ = engine.start(at: start)
        _ = engine.addLocation(LocationSample(timestamp: start.addingTimeInterval(1), latitude: 51.5, longitude: -0.1))
        // Inaccurate fix and a teleport.
        _ = engine.addLocation(LocationSample(timestamp: start.addingTimeInterval(2), latitude: 51.6, longitude: -0.1, horizontalAccuracy: 80))
        _ = engine.addLocation(LocationSample(timestamp: start.addingTimeInterval(3), latitude: 51.51, longitude: -0.1))
        XCTAssertEqual(engine.summary().distanceMeters, 0)
    }

    func testHeartRateAveraging() {
        var engine = RunEngine(structure: steady(5000))
        _ = engine.start(at: start)
        engine.addHeartRate(150, at: start)
        engine.addHeartRate(160, at: start)
        engine.addHeartRate(400, at: start) // rejected
        let summary = engine.summary()
        XCTAssertEqual(summary.averageHeartRate, 155)
        XCTAssertEqual(summary.maxHeartRate, 160)
        XCTAssertEqual(engine.snapshot().heartRate, 160)
    }
}

final class AnnouncerTests: XCTestCase {
    func testDurationAndDistancePhrases() {
        XCTAssertEqual(Announcer.durationText(90), "1 minute 30 seconds")
        XCTAssertEqual(Announcer.durationText(600), "10 minutes")
        XCTAssertEqual(Announcer.durationText(45), "45 seconds")
        XCTAssertEqual(Announcer.distanceText(800, units: .metric), "800 metres")
        XCTAssertEqual(Announcer.distanceText(5000, units: .metric), "5 kilometres")
        XCTAssertEqual(Announcer.distanceText(1609.344, units: .imperial), "1 mile")
    }
}

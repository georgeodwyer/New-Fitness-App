import XCTest
@testable import TrainingEngine

final class WatchMirrorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_792_049_400)

    private var structure: RunStructure {
        RunStructure(segments: [
            RunSegment(kind: .warmUp, length: .duration(seconds: 120)),
            RunSegment(kind: .work, length: .distance(meters: 400), targetPace: PaceRange(fastest: Pace(secondsPerKm: 230), slowest: Pace(secondsPerKm: 240)))
        ])
    }

    /// A run part-way through, as the phone would have it.
    private func midRun() -> (snapshot: RunSnapshot, events: [RunEvent]) {
        let runner = SimulatedRunner(structure: structure, driftMeters: 0, speedNoise: 0)
        var engine = RunEngine(structure: structure)
        var events = engine.start(at: start)
        for sample in runner.samples(start: start, duration: 200) {
            events += engine.addLocation(sample)
            events += engine.tick(at: sample.timestamp)
        }
        engine.addHeartRate(152, at: start.addingTimeInterval(200))
        return (engine.snapshot(), events)
    }

    func testFrameRoundTripsWithoutTheCueDetails() throws {
        var (snapshot, _) = midRun()
        snapshot.lastCue = PaceCue(direction: .tooSlow, pace: Pace(secondsPerKm: 260),
                                   target: PaceRange(fastest: Pace(secondsPerKm: 230), slowest: Pace(secondsPerKm: 240)), message: "Speed up")
        let frame = MirrorFrame(runId: UUID(), title: "Intervals", units: .imperial, isStructured: true, snapshot: snapshot,
                                alerts: [.newStep, .speedUp], sentAt: start)
        XCTAssertNil(frame.snapshot.lastCue)

        let decoded = try XCTUnwrap(MirrorMessage.decode(MirrorMessage.frame(frame).encoded()))
        guard case .frame(let back) = decoded else { return XCTFail("Expected a frame") }
        XCTAssertEqual(back, frame)
        XCTAssertEqual(back.snapshot.segment?.kind, snapshot.segment?.kind)
        XCTAssertEqual(back.snapshot.heartRate, 152)
        XCTAssertEqual(back.snapshot.distanceMeters, snapshot.distanceMeters, accuracy: 0.001)
        XCTAssertEqual(back.alerts, [.newStep, .speedUp])
    }

    func testOtherMessagesRoundTrip() throws {
        let id = UUID()
        let messages: [MirrorMessage] = [
            .ended(runId: id, saved: true),
            .ended(runId: nil, saved: false),
            .command(.pause), .command(.resume), .command(.skipStep), .command(.end),
            .heartRate(bpm: 148, at: start)
        ]
        for message in messages {
            XCTAssertEqual(MirrorMessage.decode(message.encoded()), message)
        }
        XCTAssertNil(MirrorMessage.decode(Data("nonsense".utf8)))
    }

    func testAlertsForEachEvent() {
        let (_, events) = midRun()
        XCTAssertTrue(events.map(MirrorAlert.init(event:)).contains(.newStep), "Starting the work rep taps the wrist")
        let range = PaceRange(fastest: Pace(secondsPerKm: 230), slowest: Pace(secondsPerKm: 240))
        let slow = PaceCue(direction: .tooSlow, pace: Pace(secondsPerKm: 260), target: range, message: "")
        let fast = PaceCue(direction: .tooFast, pace: Pace(secondsPerKm: 210), target: range, message: "")
        XCTAssertEqual(MirrorAlert(event: .paceCue(slow)), .speedUp)
        XCTAssertEqual(MirrorAlert(event: .paceCue(fast)), .easeOff)
        XCTAssertEqual(MirrorAlert(event: .workoutComplete(announcement: "")), .complete)
    }

    func testFreshness() {
        let frame = MirrorFrame(runId: UUID(), title: "Run", units: .metric, isStructured: false, snapshot: midRun().snapshot, sentAt: start)
        XCTAssertTrue(frame.isFresh(at: start.addingTimeInterval(10)))
        XCTAssertFalse(frame.isFresh(at: start.addingTimeInterval(16)))
    }

    func testGymFrameRoundTripsAndZones() throws {
        let frame = GymMirrorFrame(sessionId: UUID(), title: "Push", exercise: "Bench Press", setText: "Set 2 of 3 · 60 kg × 8",
                                   setStartedAt: Date(timeIntervalSince1970: 1_000), restEndsAt: nil, setsDone: 1, setsTotal: 9,
                                   zoneStarts: [95, 114, 133, 152, 171], maxHeartRate: 190, sentAt: Date(timeIntervalSince1970: 1_005))
        let decoded = try XCTUnwrap(MirrorMessage.decode(MirrorMessage.gymFrame(frame).encoded()))
        XCTAssertEqual(decoded, .gymFrame(frame))
        XCTAssertEqual(frame.zone(for: 80), 0)
        XCTAssertEqual(frame.zone(for: 140), 3)
        XCTAssertEqual(frame.zone(for: 185), 5)
        XCTAssertFalse(frame.isComplete)
        XCTAssertEqual(MirrorMessage.decode(MirrorMessage.command(.finishSet).encoded()), .command(.finishSet))
    }
}

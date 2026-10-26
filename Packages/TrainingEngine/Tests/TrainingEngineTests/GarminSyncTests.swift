import XCTest
@testable import TrainingEngine

final class GarminSyncTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_049_400)

    private var structure: RunStructure {
        RunStructure(segments: [
            RunSegment(kind: .warmUp, length: .duration(seconds: 600), label: "Warm-up"),
            RunSegment(kind: .work, length: .distance(meters: 800),
                       targetPace: PaceRange(fastest: Pace(secondsPerKm: 235), slowest: Pace(secondsPerKm: 245)), label: "Interval"),
            RunSegment(kind: .recovery, length: .duration(seconds: 90)),
            RunSegment(kind: .coolDown, length: .distance(meters: 1500))
        ])
    }

    func testPlanMessageUsesShortKeysAndPlainValues() throws {
        let option = WatchRunOption(id: UUID(), source: .planned, title: "Intervals", detail: "4 × 800 m", date: now,
                                    structure: structure, typicalEffort: 8)
        let free = WatchRunOption(id: UUID(), source: .free, title: "Free run")
        let plan = WatchPlan(generatedAt: now, units: .imperial, coaching: CoachingConfig(paceCueDelaySeconds: 15, units: .imperial),
                             runs: [option, free])
        let message = GarminSync.planMessage(plan)
        XCTAssertEqual(message["t"] as? String, "plan")
        XCTAssertEqual(message["u"] as? String, "mi")
        XCTAssertEqual(message["cue"] as? Int, 15)
        let sessions = try XCTUnwrap(message["s"] as? [[String: Any]])
        XCTAssertEqual(sessions.count, 1, "Free runs aren't sent; the watch has its own")
        XCTAssertEqual(sessions[0]["id"] as? String, option.id.uuidString)
        XCTAssertEqual(sessions[0]["day"] as? Int, 1_792_049_400)
        let steps = try XCTUnwrap(sessions[0]["st"] as? [[String: Any]])
        XCTAssertEqual(steps.count, 4)
        XCTAssertEqual(steps[0]["k"] as? String, "u")
        XCTAssertEqual(steps[0]["sec"] as? Int, 600)
        XCTAssertEqual(steps[1]["k"] as? String, "w")
        XCTAssertEqual(steps[1]["m"] as? Int, 800)
        XCTAssertEqual(steps[1]["f"] as? Int, 235)
        XCTAssertEqual(steps[1]["sl"] as? Int, 245)
        XCTAssertEqual(steps[2]["f"] as? Int, 0, "No target")
        // Everything must be a string, number or array/dictionary of them for Garmin's link.
        XCTAssertTrue(JSONSerialization.isValidJSONObject(message))
    }

    func testResultBecomesARunAgainstThePlan() throws {
        let option = WatchRunOption(id: UUID(), source: .planned, title: "Intervals", structure: structure, typicalEffort: 8)
        let message: [String: Any] = [
            "t": "result", "rid": "1792049400-123", "id": option.id.uuidString, "src": "planned", "n": "Intervals",
            "start": 1_792_049_400, "end": 1_792_051_500, "dur": 1_900.0, "dist": 5_200.0, "hr": 151, "hrx": 178,
            "seg": [
                ["i": 0, "dur": 600, "dist": 1_700, "in": 0, "ms": 0, "hr": 135],
                ["i": 1, "dur": 192, "dist": 800, "in": 180, "ms": 190, "hr": 170],
                ["i": 2, "dur": 90, "dist": 200, "in": 0, "ms": 0],
                ["i": 9, "dur": 10, "dist": 10] // not in the plan: ignored
            ],
            "spl": [[300, 140], [280, 150], [270, 160]]
        ]
        let result = try XCTUnwrap(GarminSync.result(from: message, option: option, units: .metric))
        XCTAssertEqual(result.option.id, option.id)
        XCTAssertEqual(result.summary.distanceMeters, 5_200)
        XCTAssertEqual(result.summary.durationSeconds, 1_900)
        XCTAssertEqual(result.summary.segments.count, 3)
        XCTAssertEqual(result.summary.segments[1].segment.kind, .work)
        XCTAssertEqual(try XCTUnwrap(result.summary.segments[1].averagePace?.secondsPerKm), 240, accuracy: 0.5)
        XCTAssertEqual(result.summary.timeInTargetSeconds, 180, "Only work steps with a target count")
        XCTAssertEqual(result.summary.targetedSeconds, 190)
        XCTAssertEqual(result.summary.splits.count, 3)
        XCTAssertEqual(result.summary.splits[1].pace.secondsPerKm, 280, accuracy: 0.1)
        XCTAssertEqual(result.summary.splits[2].averagePace.secondsPerKm, 850.0 / 3, accuracy: 0.1)
        XCTAssertEqual(result.summary.averageHeartRate, 151)
        XCTAssertEqual(result.effort, 8)
        // The same result twice gets the same id, so it's only saved once.
        XCTAssertEqual(GarminSync.result(from: message, option: option, units: .metric)?.id, result.id)
    }

    func testFreeRunAndBadMessages() throws {
        let free: [String: Any] = ["t": "result", "rid": "abc", "id": "", "src": "free", "n": "",
                                   "start": 1_792_049_400, "end": 1_792_051_200, "dur": 1_800, "dist": 6_000,
                                   "lap": [[600, 2_000, 0], [600, 2_000, 150]]]
        let result = try XCTUnwrap(GarminSync.result(from: free, option: nil, units: .metric))
        XCTAssertEqual(result.option.source, .free)
        XCTAssertEqual(result.option.title, "Garmin run")
        XCTAssertEqual(result.summary.laps?.count, 2)
        XCTAssertEqual(result.summary.laps?.last?.endElapsedSeconds, 1_200)
        XCTAssertNil(GarminSync.result(from: ["t": "hello"], option: nil, units: .metric))
        XCTAssertNil(GarminSync.result(from: ["t": "result", "rid": "x", "start": 1, "end": 1, "dur": 0], option: nil, units: .metric))
        XCTAssertNotEqual(GarminSync.stableId("a"), GarminSync.stableId("b"))
    }
}

import XCTest
@testable import TrainingEngine

final class CustomRunTests: XCTestCase {
    private let threshold = Pace(secondsPerKm: 255) // 4:15/km

    /// The owner's example: 2 km warm-up, 2 × 10 min at 4:15/km, 2 km cool-down.
    private var thresholdSession: CustomRunWorkout {
        CustomRunWorkout(name: "Threshold", type: .tempo, blocks: [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmUp, length: .distance(meters: 2000))]),
            WorkoutBlock(repeats: 2, steps: [
                WorkoutStep(kind: .work, length: .duration(seconds: 600), target: .single(threshold)),
                WorkoutStep(kind: .recovery, length: .duration(seconds: 120))
            ]),
            WorkoutBlock(steps: [WorkoutStep(kind: .coolDown, length: .distance(meters: 2000))])
        ])
    }

    func testStructureFlattensRepeatsWithLabels() throws {
        let segments = try XCTUnwrap(thresholdSession.structure).segments
        XCTAssertEqual(segments.map(\.kind), [.warmUp, .work, .recovery, .work, .recovery, .coolDown])
        XCTAssertEqual(segments[1].label, "Rep 1 of 2")
        XCTAssertEqual(segments[3].label, "Rep 2 of 2")
        XCTAssertEqual(segments[1].targetPace, PaceRange(fastest: threshold, slowest: threshold))
        XCTAssertNil(segments[0].targetPace)
    }

    func testTrailingRecoveryIsDropped() throws {
        let workout = CustomRunWorkout(name: "Reps", type: .intervals, blocks: [
            WorkoutBlock(repeats: 3, steps: [
                WorkoutStep(kind: .work, length: .distance(meters: 400), target: .single(threshold)),
                WorkoutStep(kind: .recovery, length: .duration(seconds: 60))
            ])
        ])
        XCTAssertEqual(try XCTUnwrap(workout.structure).segments.count, 5)
    }

    func testFreeRunHasNoStructure() {
        XCTAssertNil(CustomRunWorkout.starter(for: .free, zones: nil).structure)
    }

    func testSummaryReadsLikeTheWorkout() {
        XCTAssertEqual(thresholdSession.summary(units: .metric),
                       "2 km warm-up · 2 × (10 min @ 4:15/km, 2 min easy) · 2 km cool-down")
        let range = CustomRunWorkout(name: "Easy", type: .easy, blocks: [WorkoutBlock(steps: [
            WorkoutStep(kind: .steady, length: .distance(meters: 8000),
                        target: .range(PaceRange(fastest: Pace(secondsPerKm: 300), slowest: Pace(secondsPerKm: 320))))
        ])])
        XCTAssertEqual(range.summary(units: .metric), "8 km @ 5:00–5:20/km")
        XCTAssertEqual(CustomRunWorkout.describe(.distance(meters: 800), units: .metric), "800 m")
        XCTAssertEqual(CustomRunWorkout.describe(.duration(seconds: 90), units: .metric), "1:30")
    }

    func testEstimateUsesTargetsAndDefaultPace() {
        let estimate = thresholdSession.estimate(defaultPace: Pace(secondsPerKm: 330))
        // 4 km easy (22 min) + 20 min at 4:15 (4.71 km) + 4 min easy (0.73 km).
        XCTAssertEqual(estimate.durationSeconds, 4 * 330 + 1200 + 240, accuracy: 1)
        XCTAssertEqual(estimate.distanceMeters, 4000 + 1200 / 0.255 + 240 / 0.33, accuracy: 5)
    }

    func testStartersUseZonesRoundedToFiveSeconds() throws {
        let zones = PaceZones(vdot: 45)
        for type in RecordRunType.allCases {
            let workout = CustomRunWorkout.starter(for: type, zones: zones)
            XCTAssertEqual(workout.type, type)
            XCTAssertEqual(workout.structure == nil, type == .free, "\(type)")
            for target in workout.blocks.flatMap(\.steps).compactMap(\.target) {
                XCTAssertEqual(target.middle.secondsPerKm.truncatingRemainder(dividingBy: 5), 0)
            }
        }
        let tempo = CustomRunWorkout.starter(for: .tempo, zones: nil)
        XCTAssertTrue(tempo.blocks.flatMap(\.steps).allSatisfy { $0.target == nil }, "No zones → no targets until the runner sets them")
    }

    func testWorkoutRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(thresholdSession)
        XCTAssertEqual(try JSONDecoder().decode(CustomRunWorkout.self, from: data), thresholdSession)
    }

    func testRunEngineFollowsACustomWorkout() throws {
        var engine = RunEngine(structure: thresholdSession.structure)
        let start = Date(timeIntervalSince1970: 0)
        let events = engine.start(at: start)
        XCTAssertTrue(events.contains { if case .segmentStarted(0, _, _) = $0 { return true }; return false })
        XCTAssertEqual(engine.snapshot().segment?.kind, .warmUp)
    }
}

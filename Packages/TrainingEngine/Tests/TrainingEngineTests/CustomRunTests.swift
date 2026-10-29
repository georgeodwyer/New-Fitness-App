import XCTest
@testable import TrainingEngine

final class CustomRunTests: XCTestCase {
    private let threshold = Pace(secondsPerKm: 255) // 4:15/km

    /// The owner's example: 2 km warm-up, 2 × 10 min at 4:15/km, 2 km cool-down.
    private var thresholdSession: CustomRunWorkout {
        CustomRunWorkout(name: "Threshold", type: .tempo, blocks: [
            RunBlock(steps: [WorkoutStep(kind: .warmUp, length: .distance(meters: 2000))]),
            RunBlock(repeats: 2, steps: [
                WorkoutStep(kind: .work, length: .duration(seconds: 600), target: .single(threshold)),
                WorkoutStep(kind: .recovery, length: .duration(seconds: 120))
            ]),
            RunBlock(steps: [WorkoutStep(kind: .coolDown, length: .distance(meters: 2000))])
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
            RunBlock(repeats: 3, steps: [
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
        let range = CustomRunWorkout(name: "Easy", type: .easy, blocks: [RunBlock(steps: [
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

    func testRaceIsOneLabelledStepOfTheDistance() throws {
        let race = CustomRunWorkout.race(meters: 10000, zones: PaceZones(vdot: 45))
        XCTAssertEqual(race.name, "10K race")
        XCTAssertEqual(race.raceMeters, 10000)
        let segments = try XCTUnwrap(race.structure).segments
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].label, "Race", "The run summary finds the race by this label")
        XCTAssertNotNil(segments[0].targetPace)
        XCTAssertEqual(CustomRunWorkout.race(meters: 7500, zones: nil).name, "7.5 km race")
        XCTAssertNil(CustomRunWorkout.starter(for: .tempo, zones: nil).raceMeters)
    }

    func testWorkoutRoundTripsThroughJSON() throws {
        let workout = thresholdSession // built once: each build gets fresh ids
        let data = try JSONEncoder().encode(workout)
        XCTAssertEqual(try JSONDecoder().decode(CustomRunWorkout.self, from: data), workout)
    }

    func testRunEngineFollowsACustomWorkout() throws {
        var engine = RunEngine(structure: thresholdSession.structure)
        let start = Date(timeIntervalSince1970: 0)
        let events = engine.start(at: start)
        XCTAssertTrue(events.contains { if case .segmentStarted(0, _, _) = $0 { return true }; return false })
        XCTAssertEqual(engine.snapshot().segment?.kind, .warmUp)
    }

    func testFinishedRunFoldsIntoBlocks() throws {
        let target = PaceRange(fastest: Pace(secondsPerKm: 235), slowest: Pace(secondsPerKm: 245))
        var segments = [RunSegment(kind: .warmUp, length: .distance(meters: 2000))]
        for rep in 1...4 {
            segments.append(RunSegment(kind: .work, length: .distance(meters: 800), targetPace: target, label: "Rep \(rep) of 4"))
            if rep < 4 { segments.append(RunSegment(kind: .recovery, length: .duration(seconds: 90))) }
        }
        segments.append(RunSegment(kind: .coolDown, length: .distance(meters: 1500)))
        let workout = CustomRunWorkout(name: "Intervals", type: .intervals, structure: RunStructure(segments: segments))
        XCTAssertEqual(workout.blocks.count, 3)
        XCTAssertEqual(workout.blocks[0].steps.map(\.kind), [.warmUp])
        XCTAssertEqual(workout.blocks[1].repeats, 4)
        XCTAssertEqual(workout.blocks[1].steps.map(\.kind), [.work, .recovery])
        XCTAssertEqual(workout.blocks[1].steps[0].target, .range(target))
        XCTAssertEqual(workout.blocks[2].steps.map(\.kind), [.coolDown])

        // A progression run (no repeats) stays as one block of its steps.
        let progression = RunStructure(segments: [
            RunSegment(kind: .steady, length: .distance(meters: 3000)),
            RunSegment(kind: .steady, length: .distance(meters: 2000), targetPace: target),
            RunSegment(kind: .work, length: .distance(meters: 1000), targetPace: target)
        ])
        let single = CustomRunWorkout(name: "Progression", type: .tempo, structure: progression)
        XCTAssertEqual(single.blocks.count, 1)
        XCTAssertEqual(single.blocks[0].steps.count, 3)
        XCTAssertEqual(RecordRunType(session: .intervals), .intervals)
    }

    func testNewBlocksGoAboveTheCoolDown() {
        var workout = CustomRunWorkout(name: "Test", type: .intervals, blocks: [
            RunBlock(steps: [WorkoutStep(kind: .warmUp, length: .distance(meters: 2000))]),
            RunBlock(steps: [WorkoutStep(kind: .coolDown, length: .distance(meters: 1000))])
        ])
        workout.insert(RunBlock(repeats: 4, steps: [WorkoutStep(kind: .work, length: .duration(seconds: 60)),
                                                    WorkoutStep(kind: .recovery, length: .duration(seconds: 60))]))
        XCTAssertEqual(workout.blocks.map { $0.steps.first?.kind }, [.warmUp, .work, .coolDown])
        workout.insert(RunBlock(steps: [WorkoutStep(kind: .warmUp, length: .distance(meters: 1000))]))
        XCTAssertEqual(workout.blocks.first?.steps.first?.kind, .warmUp)
        XCTAssertEqual(workout.blocks.count, 4)

        workout.moveBlock(at: 3, by: -1)
        XCTAssertEqual(workout.blocks.map { $0.steps.first?.kind }, [.warmUp, .warmUp, .coolDown, .work])
        workout.moveBlock(at: 0, by: -1) // already at the top: nothing happens
        XCTAssertEqual(workout.blocks.count, 4)
    }
}

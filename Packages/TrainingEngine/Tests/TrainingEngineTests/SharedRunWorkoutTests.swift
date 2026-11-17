import XCTest
@testable import TrainingEngine

final class SharedRunWorkoutTests: XCTestCase {
    private let fast = PaceZones(race: RaceResult(distanceMeters: 5000, timeSeconds: 20 * 60))
    private let slower = PaceZones(race: RaceResult(distanceMeters: 5000, timeSeconds: 26 * 60))

    private var workout: CustomRunWorkout {
        CustomRunWorkout(name: "6 × 800 m", type: .intervals, blocks: [
            RunBlock(steps: [WorkoutStep(kind: .warmUp, length: .distance(meters: 2000), target: .range(fast.range(for: .easy)))]),
            RunBlock(repeats: 6, steps: [
                WorkoutStep(kind: .work, length: .distance(meters: 800), target: .range(fast.range(for: .interval))),
                WorkoutStep(kind: .recovery, length: .duration(seconds: 90)),
            ]),
            RunBlock(steps: [WorkoutStep(kind: .work, length: .duration(seconds: 600), target: .single(fast.typicalPace(for: .threshold)))]),
        ])
    }

    func testAFriendGetsTheirOwnPaces() throws {
        let shared = SharedRunWorkout(workout, zones: fast)
        let data = try XCTUnwrap(shared.encoded())
        let received = try XCTUnwrap(SharedRunWorkout.decode(data)).workout(for: slower)

        XCTAssertEqual(received.name, "6 × 800 m")
        XCTAssertEqual(received.blocks.map(\.repeats), [1, 6, 1])
        XCTAssertEqual(received.blocks[1].steps[1].length, .duration(seconds: 90))
        XCTAssertNil(received.blocks[1].steps[1].target)
        // Their interval pace, to the second.
        let reps = try XCTUnwrap(received.blocks[1].steps[0].target?.range)
        XCTAssertEqual(reps.fastest.secondsPerKm, slower.range(for: .interval).fastest.secondsPerKm, accuracy: 1)
        XCTAssertEqual(reps.slowest.secondsPerKm, slower.range(for: .interval).slowest.secondsPerKm, accuracy: 1)
        // A single pace stays single, at their threshold.
        guard case .single(let tempo)? = received.blocks[2].steps[0].target else { return XCTFail("Expected a single pace") }
        XCTAssertEqual(tempo.secondsPerKm, slower.typicalPace(for: .threshold).secondsPerKm, accuracy: 2)
        XCTAssertGreaterThan(tempo.secondsPerKm, fast.typicalPace(for: .threshold).secondsPerKm + 30)
        XCTAssertEqual(SharedRunWorkout.effortName(try XCTUnwrap(shared.blocks[1].steps[0].effort)), "Interval")
    }

    func testWithoutZonesTheSendersPacesAreKept() throws {
        let received = SharedRunWorkout(workout, zones: fast).workout(for: nil)
        let reps = try XCTUnwrap(received.blocks[1].steps[0].target?.range)
        XCTAssertEqual(reps.fastest.secondsPerKm, fast.range(for: .interval).fastest.secondsPerKm.rounded())
    }

    func testANewerFormatIsRefused() throws {
        var shared = SharedRunWorkout(workout, zones: fast)
        shared.format = 99
        XCTAssertNil(SharedRunWorkout.decode(try XCTUnwrap(shared.encoded())))
        XCTAssertNil(SharedRunWorkout.decode(Data("nonsense".utf8)))
    }
}

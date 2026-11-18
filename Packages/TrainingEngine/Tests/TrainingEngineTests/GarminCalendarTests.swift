import XCTest
@testable import TrainingEngine

final class GarminCalendarTests: XCTestCase {
    private let interval = PaceRange(fastest: Pace(secondsPerKm: 240), slowest: Pace(secondsPerKm: 250))
    private let easy = PaceRange(fastest: Pace(secondsPerKm: 330), slowest: Pace(secondsPerKm: 370))

    func testIntervalsBecomeARepeatBlock() throws {
        var segments = [RunSegment(kind: .warmUp, length: .distance(meters: 2000), targetPace: easy, paceIsGuide: true)]
        for _ in 0..<6 {
            segments.append(RunSegment(kind: .work, length: .distance(meters: 800), targetPace: interval))
            segments.append(RunSegment(kind: .recovery, length: .duration(seconds: 90)))
        }
        segments.append(RunSegment(kind: .coolDown, length: .distance(meters: 1500)))
        let workout = GarminCalendar.workout(title: "Intervals", structure: RunStructure(segments: segments))

        XCTAssertEqual(workout.steps.count, 3)
        guard case .step(let warmUp) = workout.steps[0], case .repeats(let block) = workout.steps[1],
              case .step(let coolDown) = workout.steps[2] else { return XCTFail("Expected warm-up, repeat, cool-down") }
        XCTAssertEqual(warmUp.intensity, "WARMUP")
        XCTAssertEqual(warmUp.targetType, "OPEN", "Run by effort: no pace target")
        XCTAssertEqual(block.repeatValue, 6)
        XCTAssertEqual(block.steps.map(\.intensity), ["INTERVAL", "RECOVERY"])
        XCTAssertEqual(block.steps[0].durationType, "DISTANCE")
        XCTAssertEqual(block.steps[0].durationValue, 800)
        XCTAssertEqual(block.steps[1].durationType, "TIME")
        XCTAssertEqual(try XCTUnwrap(block.steps[0].targetValueLow), 4.0, accuracy: 0.001)   // 4:10/km
        XCTAssertEqual(try XCTUnwrap(block.steps[0].targetValueHigh), 4.167, accuracy: 0.001) // 4:00/km
        XCTAssertEqual(coolDown.intensity, "COOLDOWN")
        // Step order counts every step, inside repeats too.
        XCTAssertEqual([warmUp.stepOrder, block.stepOrder] + block.steps.map(\.stepOrder) + [coolDown.stepOrder], [1, 2, 3, 4, 5])
    }

    func testEncodesForTheServer() throws {
        let workout = GarminCalendar.workout(title: "Easy run", structure: RunStructure(segments: [
            RunSegment(kind: .steady, length: .duration(seconds: 2400), targetPace: easy)]))
        let scheduled = GarminCalendar.Scheduled(sessionId: "abc", date: "2026-11-20", workout: workout)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(scheduled), encoding: .utf8))
        XCTAssertTrue(json.contains("\"sport\":\"RUNNING\""))
        XCTAssertTrue(json.contains("\"type\":\"WorkoutStep\""))
        XCTAssertTrue(json.contains("\"targetType\":\"PACE\""))
        XCTAssertTrue(json.contains("\"date\":\"2026-11-20\""))
    }
}

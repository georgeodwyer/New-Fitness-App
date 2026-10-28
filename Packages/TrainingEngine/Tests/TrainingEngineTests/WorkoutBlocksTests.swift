import XCTest
@testable import TrainingEngine

final class WorkoutBlocksTests: XCTestCase {
    private let pace = PaceRange(fastest: Pace(secondsPerKm: 268), slowest: Pace(secondsPerKm: 274))

    func testRepeatsBecomeOneBlock() {
        let rep = RunSegment(kind: .work, length: .duration(seconds: 60), targetPace: pace)
        let jog = RunSegment(kind: .recovery, length: .duration(seconds: 60))
        var segments = [RunSegment(kind: .warmUp, length: .distance(meters: 2000))]
        for index in 0..<8 {
            segments.append(rep)
            if index < 7 { segments.append(jog) }
        }
        segments.append(RunSegment(kind: .coolDown, length: .distance(meters: 1000)))

        let blocks = WorkoutBlocks(structure: RunStructure(segments: segments))
        XCTAssertEqual(blocks.warmUp?.kind, .warmUp)
        XCTAssertEqual(blocks.coolDown?.kind, .coolDown)
        XCTAssertEqual(blocks.blocks.count, 2)
        XCTAssertEqual(blocks.blocks[0].iterations, 7)
        XCTAssertEqual(blocks.blocks[0].steps, [rep, jog])
        XCTAssertEqual(blocks.blocks[1].steps, [rep], "The last rep, with no jog after it")
    }

    func testSteadyRunIsOneBlock() {
        let steady = RunSegment(kind: .steady, length: .distance(meters: 8000), targetPace: pace)
        let blocks = WorkoutBlocks(structure: RunStructure(segments: [steady]))
        XCTAssertNil(blocks.warmUp)
        XCTAssertNil(blocks.coolDown)
        XCTAssertEqual(blocks.blocks, [WorkoutBlocks.Block(steps: [steady], iterations: 1)])
    }
}

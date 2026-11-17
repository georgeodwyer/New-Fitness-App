import XCTest
@testable import TrainingEngine

final class RunCadenceTests: XCTestCase {
    /// 20 minutes at 3 m/s and 170 steps a minute, with a 2-minute pause in the middle where
    /// the counter keeps going (walking about): those steps don't count.
    func testCadenceAndStrideFromTheStepCounter() throws {
        var engine = RunEngine(structure: nil)
        let start = Date(timeIntervalSince1970: 1_000_000)
        _ = engine.start(at: start)
        var counter = 0.0
        var meters = 0.0
        var clock = 0.0
        func run(_ seconds: Int) {
            for _ in 0..<seconds {
                clock += 1
                counter += 170.0 / 60
                meters += 3
                let at = start.addingTimeInterval(clock)
                _ = engine.addIndoorDistance(totalMeters: meters, at: at)
                engine.addSteps(total: counter, at: at)
                _ = engine.tick(at: at)
            }
        }
        engine.addSteps(total: 0, at: start)
        run(600)
        engine.pause(at: start.addingTimeInterval(clock))
        for _ in 0..<120 {
            clock += 1
            counter += 1
            engine.addSteps(total: counter, at: start.addingTimeInterval(clock))
        }
        engine.resume(at: start.addingTimeInterval(clock))
        run(600)
        let summary = engine.summary()
        let cadence = try XCTUnwrap(RunCadence.averageCadence(summary.stepSamples, durationSeconds: summary.durationSeconds))
        XCTAssertEqual(cadence, 170, accuracy: 2)
        let stride = try XCTUnwrap(RunCadence.averageStride(summary.stepSamples, distanceMeters: summary.distanceMeters,
                                                             durationSeconds: summary.durationSeconds))
        XCTAssertEqual(stride, 3 * 60 / 170.0, accuracy: 0.03)
        let splits = RunCadence.perSplit(summary.splits, samples: summary.stepSamples, splitMeters: 1000)
        XCTAssertFalse(splits.isEmpty)
        for split in splits {
            let split = try XCTUnwrap(split)
            XCTAssertEqual(split.cadence, 170, accuracy: 4)
            XCTAssertEqual(split.strideMeters, 1.06, accuracy: 0.04)
        }
        let series = RunCadence.series(summary.stepSamples)
        XCTAssertGreaterThan(series.count, 30)
        XCTAssertTrue(series.allSatisfy { abs($0.value - 170) < 5 })
    }

    func testNoStepsNoCadence() {
        var engine = RunEngine(structure: nil)
        let start = Date(timeIntervalSince1970: 1_000_000)
        _ = engine.start(at: start)
        _ = engine.tick(at: start.addingTimeInterval(600))
        XCTAssertNil(engine.summary().stepSamples)
        XCTAssertNil(RunCadence.averageCadence(nil, durationSeconds: 600))
        // Too short to judge.
        XCTAssertNil(RunCadence.averageCadence([StepSample(elapsed: 60, steps: 170)], durationSeconds: 60))
    }
}

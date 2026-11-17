import XCTest
@testable import TrainingEngine

final class PaceToolsTests: XCTestCase {
    func testPaceTimeDistance() throws {
        XCTAssertEqual(PaceTools.time(distanceMeters: 10_000, pace: Pace(secondsPerKm: 300)), 3000)
        XCTAssertEqual(try XCTUnwrap(PaceTools.pace(distanceMeters: 5000, seconds: 1200)).secondsPerKm, 240)
        XCTAssertEqual(try XCTUnwrap(PaceTools.distance(seconds: 3600, pace: Pace(secondsPerKm: 300))), 12_000)
        XCTAssertNil(PaceTools.pace(distanceMeters: 0, seconds: 100))
    }

    func testEvenSplitsForAHalf() throws {
        let splits = PaceTools.splits(distanceMeters: 21_097.5, goalSeconds: 100 * 60, splitMeters: 1000)
        XCTAssertEqual(splits.count, 22)
        XCTAssertEqual(try XCTUnwrap(splits.last).meters, 97.5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(splits.last).cumulativeSeconds, 6000, accuracy: 0.01)
        XCTAssertEqual(splits[0].pace.secondsPerKm, splits[10].pace.secondsPerKm, accuracy: 0.01)
    }

    func testNegativeSplitsStillHitTheGoal() throws {
        let splits = PaceTools.splits(distanceMeters: 10_000, goalSeconds: 50 * 60, splitMeters: 1000, negativeSplit: 0.03)
        XCTAssertEqual(try XCTUnwrap(splits.last).cumulativeSeconds, 3000, accuracy: 0.01)
        XCTAssertGreaterThan(splits[0].seconds, splits[9].seconds)
        let firstHalf = splits[4].cumulativeSeconds
        let secondHalf = 3000 - firstHalf
        XCTAssertEqual((firstHalf - secondHalf) / 1500, 0.03, accuracy: 0.005)
    }
}

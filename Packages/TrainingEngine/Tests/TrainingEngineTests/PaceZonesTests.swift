import XCTest
@testable import TrainingEngine

final class PaceZonesTests: XCTestCase {
    func testVDOTMatchesDanielsTable() {
        // Daniels: a 20:00 5k is a VDOT of ~49.8.
        let vdot = PaceZones.vdot(for: RaceResult(distanceMeters: 5000, timeSeconds: 20 * 60))
        XCTAssertEqual(vdot, 49.8, accuracy: 0.3)
    }

    func testThresholdPaceForTwentyMinute5k() {
        let zones = PaceZones(race: RaceResult(distanceMeters: 5000, timeSeconds: 20 * 60))
        let threshold = zones.range(for: .threshold)
        // Daniels T-pace for VDOT 50 is ~4:15/km.
        XCTAssertEqual(threshold.fastest.secondsPerKm, 254, accuracy: 4)
        XCTAssertEqual(threshold.slowest.secondsPerKm, 261, accuracy: 4)
    }

    func testZonesAreOrderedSlowToFast() {
        let zones = PaceZones(race: RaceResult(distanceMeters: 10000, timeSeconds: 50 * 60))
        let order: [PaceZone] = [.easy, .marathon, .threshold, .interval, .repetition]
        for (slower, faster) in zip(order, order.dropFirst()) {
            XCTAssertGreaterThan(zones.typicalPace(for: slower).secondsPerKm, zones.typicalPace(for: faster).secondsPerKm,
                                 "\(slower) should be slower than \(faster)")
        }
    }

    func testDefaultZonesWhenNoRaceTime() {
        let beginner = PaceZones(profile: TestSupport.profile(running: .beginner, race: nil))
        let advanced = PaceZones(profile: TestSupport.profile(running: .advanced, race: nil))
        XCTAssertLessThan(beginner.vdot, advanced.vdot)
        XCTAssertEqual(beginner.vdot, PaceZones.vdot(for: RaceResult(distanceMeters: 5000, timeSeconds: 33 * 60)), accuracy: 0.001)
    }

    func testRacePredictionRoundTripsAndScales() {
        let race = RaceResult(distanceMeters: 5000, timeSeconds: 20 * 60)
        let zones = PaceZones(race: race)
        XCTAssertEqual(zones.predictedTime(distanceMeters: 5000), 1200, accuracy: 2)
        // Daniels equivalent 10k for VDOT ~50 is ~41:30.
        XCTAssertEqual(zones.predictedTime(distanceMeters: 10000), 41.5 * 60, accuracy: 45)
    }
}

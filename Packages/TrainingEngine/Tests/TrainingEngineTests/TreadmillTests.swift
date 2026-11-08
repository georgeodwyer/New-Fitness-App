import XCTest
@testable import TrainingEngine

final class TreadmillTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 2_000_000)

    /// 3.3 m/s from a running total for `seconds`.
    private func run(_ engine: inout RunEngine, seconds: Int, speed: Double = 3.3) -> [RunEvent] {
        var events = engine.start(at: start)
        for t in 0...seconds {
            let at = start.addingTimeInterval(Double(t))
            events += engine.addIndoorDistance(totalMeters: Double(t) * speed, at: at)
            events += engine.tick(at: at)
        }
        return events
    }

    func testIndoorDistanceGivesPaceAndSplits() {
        var engine = RunEngine(structure: nil)
        let events = run(&engine, seconds: 700)
        let summary = engine.summary()
        XCTAssertEqual(summary.distanceMeters, 2310, accuracy: 5)
        XCTAssertEqual(summary.splits.count, 2)
        XCTAssertEqual(summary.splits.first?.durationSeconds ?? 0, 303, accuracy: 2)
        XCTAssertTrue(events.contains { if case .split = $0 { return true }; return false })
        XCTAssertEqual(engine.snapshot().currentPace?.secondsPerKm ?? 0, 303, accuracy: 5)
    }

    func testCorrectedToWhatTheTreadmillSaid() {
        var engine = RunEngine(structure: nil)
        _ = run(&engine, seconds: 700)
        let corrected = engine.summary().correctedDistance(to: 2500, units: .metric)
        XCTAssertEqual(corrected.distanceMeters, 2500)
        XCTAssertEqual(corrected.splits.count, 2)
        // Faster than the step counter thought: about 280 s a kilometre.
        XCTAssertEqual(corrected.splits.first?.durationSeconds ?? 0, 280, accuracy: 3)
        XCTAssertEqual(corrected.averagePace?.secondsPerKm ?? 0, 280, accuracy: 1)
        XCTAssertEqual(TreadmillSpeed.text(kilometresPerHour: 12, units: .metric), "12.0 km/h")
        XCTAssertEqual(TreadmillSpeed.spoken(kilometresPerHour: 12.5, units: .metric), "12.5 kilometres an hour")
    }
}

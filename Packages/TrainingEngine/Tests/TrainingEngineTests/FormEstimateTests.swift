import XCTest
@testable import TrainingEngine

final class FormEstimateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testFasterRunsRaiseTheEstimate() {
        let current = PaceZones.vdot(for: RaceResult(distanceMeters: 10000, timeSeconds: 46 * 60))
        // Two recent runs with 5K efforts of 21:30 (faster than a 46:00 10K suggests).
        let runs = [
            FormEstimate.Evidence(date: now.addingTimeInterval(-3 * 86_400), bestEfforts: [.fiveK: 21.5 * 60, .oneKilometre: 250.0]),
            FormEstimate.Evidence(date: now.addingTimeInterval(-10 * 86_400), bestEfforts: [.fiveK: 21.7 * 60])
        ]
        let result = try! XCTUnwrap(FormEstimate.estimate(runs, current: current, now: now))
        XCTAssertGreaterThan(result.vdot, current)
        XCTAssertLessThanOrEqual(result.vdot, current * 1.05 + 0.0001, "Held within 5%")
        XCTAssertEqual(result.sessions, 2)
    }

    func testOldOrThinEvidenceGivesNothing() {
        let old = FormEstimate.Evidence(date: now.addingTimeInterval(-60 * 86_400), bestEfforts: [.fiveK: 20.0 * 60, .tenK: 42.0 * 60])
        XCTAssertNil(FormEstimate.estimate([old], current: 45, now: now))
        let single = FormEstimate.Evidence(date: now, bestEfforts: [.fiveK: 22.0 * 60])
        XCTAssertNil(FormEstimate.estimate([single], current: 45, now: now))
    }
}

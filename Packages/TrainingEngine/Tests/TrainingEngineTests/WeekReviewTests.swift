import XCTest
@testable import TrainingEngine

final class WeekReviewTests: XCTestCase {
    func testCountsAndHeadline() {
        let planned: [WeekReview.Session] = [
            .init(discipline: .run, status: .completed, plannedMeters: 8000),
            .init(discipline: .run, status: .completed, plannedMeters: 10000),
            .init(discipline: .strength, status: .completed),
            .init(discipline: .run, status: .skipped, plannedMeters: 6000),
            .init(discipline: .crossTraining, status: .planned)
        ]
        let review = WeekReview.make(planned: planned, runMeters: 18500, runs: 2, lifts: 1, loadRatio: 0.95, newBests: [])
        XCTAssertEqual(review.sessionsDone, 3)
        XCTAssertEqual(review.sessionsPlanned, 4, "Optional cardio not done doesn't count against you")
        XCTAssertEqual(review.plannedRunMeters, 24000)
        XCTAssertTrue(review.headline.hasPrefix("Solid week"))

        let all = WeekReview.make(planned: [.init(discipline: .run, status: .completed)], runMeters: 5000, runs: 1, lifts: 0,
                                  loadRatio: nil, newBests: ["5K 22:10"])
        XCTAssertTrue(all.headline.contains("Every session done"))
        XCTAssertTrue(all.headline.contains("5K 22:10"))
    }
}

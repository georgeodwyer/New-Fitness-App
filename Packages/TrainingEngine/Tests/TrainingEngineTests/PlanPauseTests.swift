import XCTest
@testable import TrainingEngine

final class PlanPauseTests: XCTestCase {
    func testResumingMovesTheRestOfThePlanLater() {
        let generator = TestSupport.generator
        let calendar = TestSupport.calendar
        let outline = generator.makeOutline(for: TestSupport.profile(goal: .balancedHybrid), startingOn: TestSupport.monday)
        let resumed = outline.resumed(fromWeek: 2, laterBy: 3, easeFirstWeek: true, calendar: calendar)
        XCTAssertEqual(resumed.weeks[1].startDate, outline.weeks[1].startDate, "Weeks before the pause stay")
        XCTAssertEqual(resumed.weeks[2].startDate, calendar.date(byAdding: .day, value: 21, to: outline.weeks[2].startDate))
        XCTAssertEqual(resumed.weeks.last?.startDate, calendar.date(byAdding: .day, value: 21, to: outline.weeks.last!.startDate))
        XCTAssertTrue(resumed.weeks[2].isRecoveryWeek, "An easier first week back")
        XCTAssertEqual(resumed.weekIndex(containing: calendar.date(byAdding: .day, value: 35, to: TestSupport.monday)!, calendar: calendar), 2)
    }
}

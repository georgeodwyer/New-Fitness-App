import XCTest
@testable import TrainingEngine

final class NotificationBudgetTests: XCTestCase {
    private let monday = TestSupport.monday
    private var tuesday: Date { TestSupport.calendar.date(byAdding: .day, value: 1, to: monday)! }

    func testTheMostImportantThreeADayWin() {
        typealias C = NotificationBudget.Candidate
        let candidates = [
            C(id: "bed", day: monday, priority: 10), C(id: "morning", day: monday, priority: 0),
            C(id: "preview", day: monday, priority: 8), C(id: "checkin", day: monday, priority: 4),
            C(id: "todo", day: monday, priority: 2), C(id: "result", day: monday, priority: 0, exempt: true),
            C(id: "tue.morning", day: tuesday, priority: 0)
        ]
        let picked = NotificationBudget.pick(candidates)
        XCTAssertEqual(picked, ["morning", "todo", "checkin", "result", "tue.morning"])
        XCTAssertEqual(NotificationBudget.countByDay(candidates, picked: picked)[monday], 3)
    }

    func testRoomAlreadyUsedCounts() {
        let candidates = [NotificationBudget.Candidate(id: "steps", day: monday, priority: 9)]
        XCTAssertTrue(NotificationBudget.pick(candidates, used: [monday: 3]).isEmpty)
        XCTAssertEqual(NotificationBudget.pick(candidates, used: [monday: 2]), ["steps"])
    }
}

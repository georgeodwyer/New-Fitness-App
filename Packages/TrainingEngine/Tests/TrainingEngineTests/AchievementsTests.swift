import XCTest
@testable import TrainingEngine

final class AchievementsTests: XCTestCase {
    func testLevelsAndProgress() throws {
        let all = Achievements.make(AchievementStats(checkIns: 50, runs: 12, runMeters: 104_500, gymSessions: 0))
        let checkIns = try XCTUnwrap(all.first { $0.kind == .checkIns })
        XCTAssertEqual(checkIns.earnedName, "50 check-ins")
        XCTAssertEqual(checkIns.nextName, "100 check-ins")
        XCTAssertEqual(checkIns.progress, 0, accuracy: 0.001)
        let runs = try XCTUnwrap(all.first { $0.kind == .runs })
        XCTAssertEqual(runs.level, 2)
        XCTAssertEqual(runs.progress, 2.0 / 15, accuracy: 0.001)
        XCTAssertEqual(all.first { $0.kind == .distance }?.earnedName, "100 km run")
        XCTAssertNil(all.first { $0.kind == .gym }?.earnedName)
    }

    func testWeekStreak() {
        let calendar = Calendar.kinetix
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: monday)! }
        // Weeks 1, 2, 3 then a gap, then week 5.
        XCTAssertEqual(Achievements.longestWeekStreak([day(0), day(2), day(9), day(20), day(30)], calendar: calendar), 3)
        XCTAssertEqual(Achievements.longestWeekStreak([], calendar: calendar), 0)
    }

    func testNewlyEarned() {
        let before = Achievements.make(AchievementStats(checkIns: 49))
        let after = Achievements.make(AchievementStats(checkIns: 50))
        XCTAssertEqual(Achievements.newlyEarned(before: before, after: after), ["50 check-ins"])
    }
}

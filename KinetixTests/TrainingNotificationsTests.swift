import XCTest
@testable import Kinetix

@MainActor
final class TrainingNotificationsTests: XCTestCase {
    private let calendar = Calendar.kinetix
    private func time(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testBedtimeFitsSleepBeforeTheFirstSession() {
        // 6:30 session: up at 5:45, 8 h sleep → asleep by 21:45 the night before.
        let early = TrainingNotifications.asleepBy(before: time(3, 6, 30), hard: false, sleepNeed: 480, day: time(3, 0))
        XCTAssertEqual(early, time(2, 21, 45))
        // Hard session: 30 minutes earlier.
        let hard = TrainingNotifications.asleepBy(before: time(3, 6, 30), hard: true, sleepNeed: 480, day: time(3, 0))
        XCTAssertEqual(hard, time(2, 21, 15))
        // Evening session only: the usual 7:00 wake-up → 23:00.
        let late = TrainingNotifications.asleepBy(before: time(3, 18), hard: false, sleepNeed: 480, day: time(3, 0))
        XCTAssertEqual(late, time(2, 23))
    }
}

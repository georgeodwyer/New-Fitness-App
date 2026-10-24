import XCTest
@testable import TrainingEngine

final class RecoveryHistoryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func days(_ values: [Double], endingOn end: Date) -> [HealthDay] {
        values.enumerated().map { index, value in
            HealthDay(date: calendar.date(byAdding: .day, value: index - (values.count - 1), to: end)!, value: value)
        }
    }

    func testMatchesTodaysScoreAndDipsOnABadNight() {
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
        // 20 steady days, then a poor last night (low HRV, high resting HR, short sleep).
        let hrv = days(Array(repeating: 60, count: 20) + [42], endingOn: end)
        let resting = days(Array(repeating: 50, count: 20) + [56], endingOn: end)
        let sleep = days(Array(repeating: 7.5, count: 20) + [5], endingOn: end)
        let history = RecoveryHistory.days(hrv: hrv, restingHeartRate: resting, sleep: sleep, lastDays: 14,
                                           endingOn: end, calendar: calendar)
        XCTAssertEqual(history.count, 14)
        let typical = history[history.count - 2].value
        let last = history.last!.value
        XCTAssertEqual(typical, 72, accuracy: 3, "A normal day for you is about 72")
        XCTAssertLessThan(last, 50, "A bad night shows as Low")

        // Last night's score matches today's calculation.
        let today = RecoveryScore.make(hrv: HRVSignal.assess(today: 42, history: Array(repeating: 60, count: 20)),
                                       restingHeartRate: RestingHeartRateSignal.assess(today: 56, history: Array(repeating: 50, count: 20)),
                                       sleepHours: 5, usualSleepHours: 7.5, checkIn: nil)
        XCTAssertEqual(last, today?.score ?? -1, accuracy: 0.01)
    }

    func testNoReadingsNoScores() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(RecoveryHistory.days(hrv: [], restingHeartRate: [], sleep: [], endingOn: end, calendar: calendar).isEmpty)
    }
}

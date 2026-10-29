import XCTest
@testable import TrainingEngine

final class OvernightReadingsTests: XCTestCase {
    func testOnlyOvernightReadingsCountForTheMorning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        func at(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
        }
        let days = OvernightReadings.days([
            (at(27, 23), 60), (at(28, 3), 70),   // overnight → 28th
            (at(28, 14), 30),                     // afternoon: ignored
            (at(28, 21), 50), (at(29, 9), 54)     // overnight → 29th
        ], calendar: calendar)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].date, calendar.startOfDay(for: at(28, 12)))
        XCTAssertEqual(days[0].value, 65)
        XCTAssertEqual(days[1].value, 52)
    }
}

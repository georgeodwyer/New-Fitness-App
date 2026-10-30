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

    func testOnlyReadingsWhileAsleepCount() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        // Asleep 23:00–02:00 and 02:30–07:00 on the night into the 28th; the watch then recorded
        // a separate shorter night from another source, which is ignored.
        let sleep = [
            SleepSample(source: "watch", start: at(27, 23), end: at(28, 2)),
            SleepSample(source: "watch", start: at(28, 2, 30), end: at(28, 7)),
            SleepSample(source: "phone", start: at(28, 1), end: at(28, 3))
        ]
        let asleep = SleepNights.periods(sleep, calendar: calendar)
        let night = calendar.startOfDay(for: at(28, 12))
        XCTAssertEqual(asleep[night]?.count, 2)

        let days = SleepReadings.days([
            (at(27, 21), 90),                      // evening, awake: ignored
            (at(28, 1), 60), (at(28, 5), 70),      // asleep → 28th
            (at(28, 2, 15), 120),                  // awake in the night: ignored
            (at(28, 8), 100),                      // awake in the morning: ignored
            (at(28, 22), 50), (at(29, 9), 54)      // no sleep recorded that night: overnight window
        ], asleep: asleep, calendar: calendar)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].date, night)
        XCTAssertEqual(days[0].value, 65)
        XCTAssertEqual(days[1].value, 52)

        let strict = SleepReadings.days([(at(28, 22), 50)], asleep: asleep, calendar: calendar, fallbackToOvernight: false)
        XCTAssertTrue(strict.isEmpty)
    }
}

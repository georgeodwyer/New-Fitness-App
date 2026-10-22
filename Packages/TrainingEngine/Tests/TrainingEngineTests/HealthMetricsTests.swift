import XCTest
@testable import TrainingEngine

final class HealthMetricsTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private lazy var today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16))!

    private func days(_ values: [Double]) -> [HealthDay] {
        // Last value is today.
        values.enumerated().map { index, value in
            HealthDay(date: calendar.date(byAdding: .day, value: index - (values.count - 1), to: today)!, value: value)
        }
    }

    func testTrendComparesWithUsual() throws {
        let trend = try XCTUnwrap(HealthTrend.make(metric: .hrv, days: days([60, 62, 58, 61, 59, 60, 63, 48]), calendar: calendar))
        XCTAssertEqual(trend.latest.value, 48)
        XCTAssertEqual(try XCTUnwrap(trend.usual), 60)
        XCTAssertEqual(trend.direction, .down)
        XCTAssertEqual(trend.isGoodChange, false)
        XCTAssertEqual(trend.comparisonText, "20% below your usual")
        XCTAssertEqual(try XCTUnwrap(trend.average7), (62 + 58 + 61 + 59 + 60 + 63 + 48) / 7, accuracy: 0.001)
    }

    func testRestingHeartRateUsesBeatsAndSteadyBand() throws {
        let steady = try XCTUnwrap(HealthTrend.make(metric: .restingHeartRate, days: days([50, 51, 49, 50, 50, 51]), calendar: calendar))
        XCTAssertEqual(steady.direction, .steady)
        XCTAssertEqual(steady.comparisonText, "about your usual")
        let raised = try XCTUnwrap(HealthTrend.make(metric: .restingHeartRate, days: days([50, 51, 49, 50, 50, 57]), calendar: calendar))
        XCTAssertEqual(raised.comparisonText, "7 bpm above your usual")
        XCTAssertEqual(raised.isGoodChange, false)
    }

    func testTooLittleHistoryHasNoUsual() throws {
        let trend = try XCTUnwrap(HealthTrend.make(metric: .steps, days: days([8000, 9000, 12000]), calendar: calendar))
        XCTAssertNil(trend.usual)
        XCTAssertNil(trend.comparisonText)
        XCTAssertNil(HealthTrend.make(metric: .steps, days: []))
    }

    func testWindowAndFormatting() {
        let all = days(Array(repeating: 7.5, count: 40))
        XCTAssertEqual(HealthSeries.window(all, lastDays: 7, endingOn: today, calendar: calendar).count, 7)
        XCTAssertEqual(HealthSeries.window(all, lastDays: 30, endingOn: today, calendar: calendar).count, 30)
        XCTAssertEqual(HealthMetric.sleep.format(7.5), "7 h 30 m")
        XCTAssertEqual(HealthMetric.restingHeartRate.format(51.6), "52")
        XCTAssertEqual(HealthMetric.vo2Max.format(48.24), "48.2")
        XCTAssertEqual(HealthMetric.steps.format(12345), "12,345")
    }

    func testHRVSignal() throws {
        let history = [60.0, 62, 58, 61, 59, 60, 63]
        let low = try XCTUnwrap(HRVSignal.assess(today: 48, history: history))
        XCTAssertTrue(low.isSuppressed)
        XCTAssertEqual(low.description, "48 ms · 20% below your usual")
        XCTAssertFalse(try XCTUnwrap(HRVSignal.assess(today: 55, history: history)).isSuppressed)
        XCTAssertNil(HRVSignal.assess(today: 48, history: [60, 61]), "Needs a week of readings first")
    }

    func testLowHRVOnlyCountsWithAMeh_CheckIn() {
        // Feeling great: one low HRV reading doesn't change the plan.
        XCTAssertFalse(RecoveryCheckIn(sleep: 5, soreness: 1, energy: 5, hrvSuppressed: true).isPoor)
        // Feeling so-so plus low HRV: poor recovery.
        XCTAssertTrue(RecoveryCheckIn(sleep: 3, soreness: 3, energy: 3, hrvSuppressed: true).isPoor)
        XCTAssertFalse(RecoveryCheckIn(sleep: 3, soreness: 3, energy: 3).isPoor)
    }

    func testSleepScore() {
        XCTAssertEqual(SleepScore.score(hours: 4.5), 1)
        XCTAssertEqual(SleepScore.score(hours: 5.5), 2)
        XCTAssertEqual(SleepScore.score(hours: 6.9), 3)
        XCTAssertEqual(SleepScore.score(hours: 7.5), 4)
        XCTAssertEqual(SleepScore.score(hours: 8.2), 5)
    }

    func testRulesFileWithoutHRVValuesStillLoads() throws {
        let json = """
        {"poorReadinessBelow": 0.42, "verySoreAtOrAbove": 5, "restingHeartRateElevatedBpm": 7,
         "restingHeartRateMinimumReadings": 7, "bodySignalCountsWhenReadinessBelow": 0.6}
        """
        let recovery = try JSONDecoder().decode(BalanceRules.Recovery.self, from: Data(json.utf8))
        XCTAssertEqual(recovery.hrvSuppressedPercent, 15)
        XCTAssertEqual(recovery.hrvMinimumReadings, 7)
        XCTAssertEqual(try BalanceRules.bundled().recovery.hrvSuppressedPercent, 15)
    }

    func testDashboardLayoutReorderHideAndUpgrade() {
        var layout = DashboardLayout.default
        XCTAssertEqual(layout.visibleCards, DashboardCard.defaultOrder)
        layout.setHidden(.records, true)
        XCTAssertFalse(layout.visibleCards.contains(.records))
        layout.move(fromOffsets: IndexSet(integer: 2), toOffset: 0) // body to the top
        XCTAssertEqual(layout.cards.first, .body)
        XCTAssertEqual(layout.cards.count, DashboardCard.allCases.count)

        // A layout saved before the Body card existed, plus a card this version doesn't know.
        let old = DashboardLayout(order: [], hidden: [])
        var saved = old
        saved.order = ["checkIn", "today", "load", "futureCard"]
        XCTAssertEqual(Array(saved.cards.prefix(3)), [.checkIn, .body, .today], "New cards appear after their default neighbour")
        XCTAssertEqual(saved.cards.count, DashboardCard.allCases.count)
        XCTAssertFalse(saved.cards.map(\.rawValue).contains("futureCard"))
    }

    func testSleepBeforeMidnightCountsForTheSameNight() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let wakeDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        func at(_ hour: Double, dayOffset: Int = 0) -> Date {
            calendar.date(byAdding: .day, value: dayOffset, to: wakeDay)!.addingTimeInterval(hour * 3600)
        }
        // Apple Watch stages every 20 minutes from 21:55 to 05:54 (about 2 hours before midnight).
        let watch = "com.apple.health.watch"
        var samples: [SleepSample] = []
        var time = at(21 + 55.0 / 60, dayOffset: -1)
        let end = at(5 + 54.0 / 60)
        while time < end {
            let next = min(time.addingTimeInterval(20 * 60), end)
            samples.append(SleepSample(source: watch, start: time, end: next))
            time = next
        }
        let days = SleepNights.days(samples, calendar: calendar)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days.first?.date, wakeDay)
        XCTAssertEqual(days.first?.value ?? 0, 7 + 59.0 / 60, accuracy: 0.01)
    }

    func testSleepOverlapsCountOnceAndLongestSourceWins() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        let night = day.addingTimeInterval(-2 * 3600) // 22:00 the evening before
        let samples = [
            // One app writes both "asleep" and stages over the same hours.
            SleepSample(source: "a", start: night, end: night.addingTimeInterval(6 * 3600)),
            SleepSample(source: "a", start: night.addingTimeInterval(3600), end: night.addingTimeInterval(4 * 3600)),
            // Another app recorded 6.5 hours.
            SleepSample(source: "b", start: night, end: night.addingTimeInterval(6.5 * 3600)),
            // An afternoon nap the next day counts towards that day too (same night window).
            SleepSample(source: "b", start: day.addingTimeInterval(14 * 3600), end: day.addingTimeInterval(14.4 * 3600))
        ]
        let days = SleepNights.days(samples, calendar: calendar)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days.first?.date, day)
        XCTAssertEqual(days.first?.value ?? 0, 6.9, accuracy: 0.01)
        // An evening nap after 6 pm belongs to the next night.
        let evening = SleepSample(source: "a", start: day.addingTimeInterval(19 * 3600), end: day.addingTimeInterval(20 * 3600))
        XCTAssertEqual(SleepNights.days([evening], calendar: calendar).first?.date, calendar.date(byAdding: .day, value: 1, to: day))
    }
}

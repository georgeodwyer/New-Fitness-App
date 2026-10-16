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
}

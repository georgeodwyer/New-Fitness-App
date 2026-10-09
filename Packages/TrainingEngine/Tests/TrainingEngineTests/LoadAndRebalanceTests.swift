import XCTest
@testable import TrainingEngine

final class LoadModelTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private var today: Date { TestSupport.date(2026, 10, 28) }

    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: -offset, to: today)! }

    func testAcuteChronicAndRatio() {
        // 4 weeks of 400 AU/week running (one 400 session each Wednesday-ish) …
        var entries = (0..<4).map { LoadEntry(date: day($0 * 7 + 2), discipline: .run, load: 400) }
        // … plus 300 AU lifting this week.
        entries.append(LoadEntry(date: day(1), discipline: .strength, load: 300))
        let report = LoadModel.report(entries: entries, today: today, calendar: calendar)

        XCTAssertEqual(report.running.acute, 400)
        XCTAssertEqual(report.running.chronic, 400)
        XCTAssertEqual(report.running.ratio ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(report.lifting.acute, 300)
        XCTAssertEqual(report.lifting.chronic, 75)
        XCTAssertEqual(report.combined.acute, 700)
        XCTAssertEqual(report.combined.chronic, 475)
        XCTAssertEqual(report.combined.ratio ?? 0, 700.0 / 475.0, accuracy: 0.001)
        XCTAssertEqual(report.combined.status, .high)
        XCTAssertEqual(report.running.status, .optimal)
    }

    func testRatioNeedsTwoWeeksOfHistory() {
        let entries = [LoadEntry(date: day(3), discipline: .run, load: 300)]
        let report = LoadModel.report(entries: entries, today: today, calendar: calendar)
        XCTAssertNil(report.combined.ratio)
        XCTAssertEqual(report.combined.status, .building)
    }

    func testUndertrained() {
        let entries = (8..<28).map { LoadEntry(date: day($0), discipline: .run, load: 100) } + [LoadEntry(date: day(1), discipline: .run, load: 100)]
        let report = LoadModel.report(entries: entries, today: today, calendar: calendar)
        XCTAssertEqual(report.combined.status, .undertrained)
    }

    func testDailySeriesCoversLast28DaysOldestFirst() {
        let entries = [LoadEntry(date: day(0).addingTimeInterval(3600 * 9), discipline: .run, load: 200),
                       LoadEntry(date: day(0).addingTimeInterval(3600 * 18), discipline: .strength, load: 250)]
        let report = LoadModel.report(entries: entries, today: today, calendar: calendar)
        XCTAssertEqual(report.daily.count, 28)
        XCTAssertEqual(report.daily.last?.running, 200)
        XCTAssertEqual(report.daily.last?.lifting, 250)
        XCTAssertEqual(report.daily.last?.total, 450)
        XCTAssertLessThan(report.daily[0].date, report.daily[27].date)
        XCTAssertEqual(report.ratioTrend.count, 56)
    }

    func testStatusThresholds() {
        XCTAssertEqual(LoadStatus.from(ratio: 0.79), .undertrained)
        XCTAssertEqual(LoadStatus.from(ratio: 0.8), .optimal)
        XCTAssertEqual(LoadStatus.from(ratio: 1.3), .optimal)
        XCTAssertEqual(LoadStatus.from(ratio: 1.31), .high)
        XCTAssertEqual(LoadStatus.from(ratio: nil), .building)
    }

    func testRecoveryCheckIn() {
        XCTAssertEqual(RecoveryCheckIn(sleep: 5, soreness: 1, energy: 5).readiness, 1)
        XCTAssertEqual(RecoveryCheckIn(sleep: 1, soreness: 5, energy: 1).readiness, 0)
        XCTAssertTrue(RecoveryCheckIn(sleep: 2, soreness: 4, energy: 2).isPoor)
        XCTAssertFalse(RecoveryCheckIn(sleep: 4, soreness: 2, energy: 4).isPoor)
        XCTAssertTrue(RecoveryCheckIn(sleep: 5, soreness: 5, energy: 5).isPoor, "Very sore always counts as poor")
    }
}

final class RebalancerTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private let monday = TestSupport.monday
    private let zones = PaceZones(race: RaceResult(distanceMeters: 5000, timeSeconds: 1320))

    private func date(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: monday)! }

    private func context(today offset: Int, days: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .saturday, .sunday]) -> Rebalancer.Context {
        Rebalancer.Context(trainingDays: days, zones: zones, units: .metric, calendar: calendar, today: date(offset))
    }

    private func session(_ day: Int, _ kind: SessionKind, key: Bool = false, slot: SessionSlot = .morning, minutes: Double = 45) -> WeekSession {
        WeekSession(id: UUID(), date: date(day), slot: slot, kind: kind, isKey: key, title: kind.displayName,
                    durationMinutes: minutes, effort: 5)
    }

    /// Mon intervals (key), Tue easy, Wed upper, Thu easy, Sat lower, Sun long (key).
    private func week() -> [WeekSession] {
        [session(0, .run(.intervals), key: true), session(1, .run(.easy)), session(2, .strength(.upper)),
         session(3, .run(.easy)), session(5, .strength(.lower)), session(6, .run(.long), key: true, minutes: 90)]
    }

    func testSkippingNonKeySessionIsNotRescheduled() {
        let week = week()
        let result = Rebalancer.skip(week[1].id, week: week, context: context(today: 1))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].session.status, .skipped)
        XCTAssertTrue(result[0].explanation.contains("won't be squeezed in"))
    }

    func testSkippedKeySessionReplacesALaterEasySession() {
        let week = week()
        // Skip Monday's intervals on Monday: Tuesday's easy run would put intervals the day before
        // nothing hard (fine) — Tue is the first valid easy slot.
        let result = Rebalancer.skip(week[0].id, week: week, context: context(today: 0))
        XCTAssertEqual(result.count, 2)
        let moved = result[0].session
        XCTAssertEqual(moved.status, .planned)
        XCTAssertEqual(calendar.weekday(of: moved.date), .tuesday)
        XCTAssertEqual(result[1].session.id, week[1].id)
        XCTAssertEqual(result[1].session.status, .skipped)
        XCTAssertTrue(result[0].explanation.contains("Tuesday"))
    }

    func testMovedKeySessionRespectsInterference() {
        var week = week()
        // Make Thursday the only easy run left and put a lower-body lift on Wednesday:
        // intervals can't go on Thursday (day after a lower lift).
        week[1].status = .completed
        week[2].kind = .strength(.lower)
        let result = Rebalancer.skip(week[0].id, week: week, context: context(today: 1))
        let moved = result.first { $0.session.id == week[0].id }!.session
        XCTAssertNotEqual(calendar.weekday(of: moved.date), .thursday)
        let final = week.map { s in result.first { $0.session.id == s.id }?.session ?? s }
        XCTAssertTrue(Rebalancer.isValid(final, calendar: calendar))
    }

    func testKeySessionDroppedWhenNoSlot() {
        // Only Sat/Sun training days: skipping Sunday's long run on Sunday leaves nowhere to go.
        let week = [session(5, .strength(.upper)), session(6, .run(.long), key: true)]
        let result = Rebalancer.skip(week[1].id, week: week, context: context(today: 6, days: [.saturday, .sunday]))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].session.status, .skipped)
        XCTAssertTrue(result[0].explanation.contains("dropped rather than stacked"))
    }

    func testSwapOptions() {
        let intervals = session(0, .run(.intervals), key: true, minutes: 55)
        let options = Rebalancer.swapOptions(for: intervals, context: context(today: 0))
        XCTAssertEqual(options.map(\.id), ["easyRun", "crossTraining", "mobility"])
        let easy = options[0].replacement
        XCTAssertEqual(easy.kind, .run(.easy))
        XCTAssertEqual(easy.status, .swapped)
        XCTAssertEqual(easy.durationMinutes, 45)
        XCTAssertNotNil(easy.runStructure)
        XCTAssertTrue(options[0].explanation.hasPrefix("Swapped your intervals"))

        var lift = session(2, .strength(.lower), minutes: 60)
        lift.strength = StrengthPrescription(exercises: [
            ExercisePrescription(exerciseId: "squat", name: "Squat", role: .main, sets: 5, repRange: RepRange(4, 6), weightKg: 100, restSeconds: 180)
        ])
        let liftOptions = Rebalancer.swapOptions(for: lift, context: context(today: 0))
        XCTAssertEqual(liftOptions.map(\.id), ["reduced", "mobility"])
        XCTAssertEqual(liftOptions[0].replacement.strength?.exercises.first?.sets, 3)
        XCTAssertEqual(liftOptions[0].replacement.strength?.exercises.first?.weightKg, 100)
    }

    func testHighLoadEasesNextNonKeyHardSessionAndTrimsEasyRuns() {
        var week = week()
        week[2].strength = StrengthPrescription(exercises: [
            ExercisePrescription(exerciseId: "bench", name: "Bench", role: .main, sets: 4, repRange: RepRange(6, 8), weightKg: 60, restSeconds: 150)
        ])
        let result = Rebalancer.adjustForLoad(week: week, status: .high, checkIn: nil, context: context(today: 1))
        // Wednesday's (non-key) upper session is reduced; Tue and Thu easy runs shortened; key sessions untouched.
        XCTAssertTrue(result.contains { $0.session.id == week[2].id && $0.session.strength?.exercises.first?.sets == 2 })
        XCTAssertTrue(result.contains { $0.session.id == week[1].id && $0.session.durationMinutes == 35 })
        XCTAssertTrue(result.contains { $0.session.id == week[3].id })
        XCTAssertFalse(result.contains { $0.session.isKey })
        XCTAssertTrue(result.allSatisfy { $0.explanation.contains("training load has spiked") })
    }

    func testPoorRecoveryEasesButDoesNotTrim() {
        var week = week()
        week[0].isKey = false // a non-key interval session today
        let result = Rebalancer.adjustForLoad(week: week, status: .optimal, checkIn: RecoveryCheckIn(sleep: 1, soreness: 4, energy: 2),
                                              context: context(today: 0))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].session.kind, .run(.easy))
        XCTAssertTrue(result[0].explanation.contains("not fully recovered"))
    }

    func testNothingChangesWhenAllIsWell() {
        XCTAssertTrue(Rebalancer.adjustForLoad(week: week(), status: .optimal, checkIn: RecoveryCheckIn(sleep: 4, soreness: 2, energy: 4),
                                               context: context(today: 0)).isEmpty)
    }

    func testAlreadyAdjustedSessionsAreLeftAlone() {
        var week = week()
        for index in week.indices { week[index].changeReason = "Already changed" }
        XCTAssertTrue(Rebalancer.adjustForLoad(week: week, status: .high, checkIn: nil, context: context(today: 0)).isEmpty)
    }
}

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
        XCTAssertEqual(report.daily.count, 30)
        XCTAssertEqual(report.daily.last?.running, 200)
        XCTAssertEqual(report.daily.last?.lifting, 250)
        XCTAssertEqual(report.daily.last?.total, 450)
        XCTAssertLessThan(report.daily[0].date, report.daily[29].date)
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

    /// Mon intervals (key), Tue easy, Wed lower, Thu easy, Sat upper, Sun long (key) — a valid week.
    private func week() -> [WeekSession] {
        [session(0, .run(.intervals), key: true), session(1, .run(.easy)), session(2, .strength(.lower)),
         session(3, .run(.easy)), session(5, .strength(.upper)), session(6, .run(.long), key: true, minutes: 90)]
    }

    func testLowRecoveryEasesTodaysHardSessions() {
        var week = week()
        let squat = ExercisePrescription(exerciseId: "squat", name: "Squat", role: .main, sets: 4, repRange: RepRange(5, 6),
                                         weightKg: 80, restSeconds: 150)
        let plank = ExercisePrescription(exerciseId: "plank", name: "Plank", role: .accessory, sets: 1, repRange: RepRange(1, 1),
                                         weightKg: nil, restSeconds: 60)
        let lift = WeekSession(id: UUID(), date: date(0), slot: .evening, kind: .strength(.lower), isKey: false, title: "Lower",
                               durationMinutes: 50, effort: 7, strength: StrengthPrescription(exercises: [squat, plank]))
        week.append(lift)

        let low = RecoveryScore(score: 42, parts: [])
        XCTAssertEqual(Rebalancer.RecoveryTaper(low), .ease)
        let eased = Rebalancer.taperForRecovery(week: week, recovery: low, context: context(today: 0))
        XCTAssertEqual(eased.count, 2, "Only today's intervals and lift")
        XCTAssertTrue(eased.allSatisfy { $0.cause == .lowRecovery })
        let run = eased.first { $0.session.id == week[0].id }
        XCTAssertEqual(run?.session.kind, .run(.easy))
        XCTAssertLessThanOrEqual(run?.session.durationMinutes ?? 99, 45)
        XCTAssertTrue(run?.explanation.contains("your recovery is low today (42)") ?? false)
        let gym = eased.first { $0.session.id == lift.id }
        XCTAssertEqual(gym?.session.strength?.exercises.map(\.sets), [3, 1], "One set fewer each, never below one")
        XCTAssertEqual(gym?.session.strength?.exercises.first?.weightKg, 80, "Same weights")
        XCTAssertTrue(gym?.session.title.hasSuffix("(lighter)") ?? false)

        // Fair: nothing changes by itself, but a lighter version is offered.
        let fair = RecoveryScore(score: 60, parts: [])
        XCTAssertEqual(Rebalancer.RecoveryTaper(fair), .offer)
        XCTAssertTrue(Rebalancer.taperForRecovery(week: week, recovery: fair, context: context(today: 0)).isEmpty)
        let offer = Rebalancer.lighterVersion(of: week[0], recovery: fair, context: context(today: 0))
        XCTAssertEqual(offer?.replacement.kind, .run(.easy))
        XCTAssertTrue(offer?.explanation.contains("fair today (60)") ?? false)

        // Good recovery, easy runs, other days and already-changed sessions are left alone.
        XCTAssertEqual(Rebalancer.RecoveryTaper(RecoveryScore(score: 80, parts: [])), .none)
        XCTAssertTrue(Rebalancer.taperForRecovery(week: week, recovery: RecoveryScore(score: 80, parts: []), context: context(today: 0)).isEmpty)
        XCTAssertNil(Rebalancer.lighterVersion(of: week[1], recovery: low, context: context(today: 1)), "Easy run")
        XCTAssertNil(Rebalancer.lighterVersion(of: week[0], recovery: low, context: context(today: 1)), "Not today")
        var changed = week[0]
        changed.changeReason = "Already eased"
        XCTAssertNil(Rebalancer.lighterVersion(of: changed, recovery: low, context: context(today: 0)))

        // A long run is shortened to an easy run of 60% of its length.
        XCTAssertEqual(Rebalancer.lighterVersion(of: week[5], recovery: low, context: context(today: 6))?.replacement.durationMinutes, 54)
    }

    func testMoveToAnotherDay() throws {
        let week = week()
        // Thursday's easy run to Friday (a free day): fine, no warning.
        let easy = try XCTUnwrap(Rebalancer.move(week[3].id, to: date(4), week: week, context: context(today: 0)))
        XCTAssertTrue(calendar.isDate(easy.adjustment.session.date, inSameDayAs: date(4)))
        XCTAssertNil(easy.warning)
        XCTAssertEqual(easy.adjustment.cause, .moved)
        XCTAssertEqual(easy.adjustment.explanation, "You moved your easy run to Friday.")
        XCTAssertNil(easy.adjustment.session.changeReason, "A moved session can still be eased later")

        // Monday's intervals to Saturday, the day before the long run: allowed, with a heads-up.
        let hard = try XCTUnwrap(Rebalancer.move(week[0].id, to: date(5), week: week, context: context(today: 0)))
        XCTAssertNotNil(hard.warning)
        XCTAssertEqual(hard.adjustment.session.slot, .evening, "Saturday morning is taken, so it goes in the evening")

        // An easy run onto a day that already has a run: two runs that day.
        let twoRuns = try XCTUnwrap(Rebalancer.move(week[1].id, to: date(6), week: week, context: context(today: 0)))
        XCTAssertTrue(twoRuns.warning?.contains("two runs") ?? false)

        // Same day, or a full day: not offered.
        XCTAssertNil(Rebalancer.move(week[1].id, to: date(1), week: week, context: context(today: 0)))
        var full = week
        full.append(session(4, .strength(.upper), slot: .morning))
        full.append(session(4, .run(.easy), slot: .evening))
        XCTAssertNil(Rebalancer.move(week[3].id, to: date(4), week: full, context: context(today: 0)))
    }

    func testBaseWeekIsValid() {
        XCTAssertTrue(Rebalancer.isValid(week(), calendar: calendar))
    }

    func testSkippingNonKeySessionIsNotRescheduled() {
        let week = week()
        let result = Rebalancer.skip(week[1].id, week: week, context: context(today: 1))
        XCTAssertTrue(result.allSatisfy { $0.cause == .skipped })
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
        // Tuesday's easy run is done, so Thursday's is the only one left — but intervals can't
        // go on Thursday (the day after Wednesday's lower-body lift), and there's no free day.
        week[1].status = .completed
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
        XCTAssertTrue(result.allSatisfy { $0.cause == .highLoad })
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

    func testReductionScalesWithRecovery() throws {
        let target = PaceRange(fastest: Pace(secondsPerKm: 235), slowest: Pace(secondsPerKm: 245))
        var segments = [RunSegment(kind: .warmUp, length: .distance(meters: 2000))]
        for rep in 1...6 {
            segments.append(RunSegment(kind: .work, length: .distance(meters: 800), targetPace: target, label: "Rep \(rep) of 6"))
            if rep < 6 { segments.append(RunSegment(kind: .recovery, length: .duration(seconds: 90))) }
        }
        segments.append(RunSegment(kind: .coolDown, length: .distance(meters: 1500)))
        let intervals = WeekSession(id: UUID(), date: date(0), slot: .morning, kind: .run(.intervals), isKey: true, title: "Intervals",
                                    durationMinutes: 60, effort: 8, runStructure: RunStructure(segments: segments))
        let tired = RecoveryScore(score: 50, parts: [])
        let option = try XCTUnwrap(Rebalancer.reduced(intervals, recovery: tired))
        XCTAssertEqual(option.title, "Reduce by 15%")
        let reps = option.replacement.runStructure?.segments.filter { $0.kind == .work } ?? []
        XCTAssertEqual(reps.count, 5, "6 reps × 0.85 → 5")
        XCTAssertEqual(reps.last?.label, "Rep 5 of 5")
        XCTAssertEqual(option.replacement.runStructure?.segments.last?.kind, .coolDown)
        XCTAssertEqual(option.replacement.runStructure?.segments.first?.kind, .warmUp)
        XCTAssertEqual(option.replacement.durationMinutes, 51)

        // A steady run gets shorter; warm-up and cool-down don't.
        let tempo = WeekSession(id: UUID(), date: date(0), slot: .morning, kind: .run(.tempo), isKey: false, title: "Tempo",
                                durationMinutes: 50, effort: 7, runStructure: RunStructure(segments: [
                                    RunSegment(kind: .warmUp, length: .distance(meters: 2000)),
                                    RunSegment(kind: .work, length: .distance(meters: 5000), targetPace: target),
                                    RunSegment(kind: .coolDown, length: .distance(meters: 1500))]))
        let shorter = try XCTUnwrap(Rebalancer.reduced(tempo, recovery: tired)).replacement.runStructure?.segments ?? []
        XCTAssertEqual(shorter[1].length, .distance(meters: 4200))
        XCTAssertEqual(shorter[0].length, .distance(meters: 2000))

        // Gym: same weights, fewer sets, at least one each.
        let gym = WeekSession(id: UUID(), date: date(0), slot: .evening, kind: .strength(.fullBody), isKey: false, title: "Push",
                              durationMinutes: 60, effort: 7, strength: StrengthPrescription(exercises: [
                                ExercisePrescription(exerciseId: "a", name: "Bench", role: .main, sets: 4, repRange: RepRange(6, 8), weightKg: 80, restSeconds: 150),
                                ExercisePrescription(exerciseId: "b", name: "Fly", role: .accessory, sets: 3, repRange: RepRange(10, 12), weightKg: 12, restSeconds: 60),
                                ExercisePrescription(exerciseId: "c", name: "Raise", role: .accessory, sets: 3, repRange: RepRange(12, 15), weightKg: 8, restSeconds: 60)]))
        let lighter = try XCTUnwrap(Rebalancer.reduced(gym, recovery: tired)).replacement.strength?.exercises ?? []
        XCTAssertEqual(lighter.reduce(0) { $0 + $1.sets }, 8, "10 sets × 0.85 → 8")
        XCTAssertEqual(lighter.map(\.weightKg), [80, 12, 8])
        XCTAssertTrue(lighter.allSatisfy { $0.sets >= 1 })

        XCTAssertNil(Rebalancer.reduced(intervals, recovery: RecoveryScore(score: 75, parts: [])), "No cut when recovery is fine")
    }
}

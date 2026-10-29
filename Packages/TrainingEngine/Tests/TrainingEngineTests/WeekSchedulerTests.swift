import XCTest
@testable import TrainingEngine

final class WeekSchedulerTests: XCTestCase {
    private let templates = TestSupport.templates

    private var lower: StrengthSessionTemplate { templates.strength.sessions["lowerA"]! }
    private var upper: StrengthSessionTemplate { templates.strength.sessions["upperA"]! }

    func testLongRunGoesOnSundayWhenAvailable() {
        let result = WeekScheduler.schedule(days: [.monday, .wednesday, .saturday, .sunday], doubleDays: 0, runs: [.long, .easy], lifts: [])
        XCTAssertEqual(result.placements.first { $0.item == .run(.long) }?.weekday, .sunday)
    }

    func testQualityRunsAreSpreadOut() {
        let days: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .sunday]
        let result = WeekScheduler.schedule(days: days, doubleDays: 0, runs: [.long, .intervals, .tempo, .easy], lifts: [])
        let hardDays = result.placements.filter(\.isHardRun).map(\.weekday)
        XCTAssertEqual(hardDays.count, 3)
        for a in hardDays {
            for b in hardDays where a != b {
                XCTAssertGreaterThanOrEqual(a.circularDistance(to: b), 2, "Hard runs on \(a) and \(b) are back to back")
            }
        }
    }

    func testLowerBodyLiftNeverDayBeforeKeyRun() {
        let days: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .saturday, .sunday]
        let result = WeekScheduler.schedule(days: days, doubleDays: 1, runs: [.long, .intervals, .easy], lifts: [lower, upper])
        XCTAssertEqual(WeekScheduler.violations(result.placements, days: days, doubleDays: 1), [])
        let lowerDay = result.placements.first { $0.loadsLowerBody }?.weekday
        XCTAssertNotNil(lowerDay)
    }

    func testLegDaysNeverShareADayWithAHardRun() {
        // Even with a double available, the lower-body lift stays off the intervals day.
        let days: [Weekday] = Weekday.allCases
        let result = WeekScheduler.schedule(days: days, doubleDays: 1, runs: [.long, .intervals, .tempo, .easy], lifts: [lower])
        let hardDays = Set(result.placements.filter(\.isHardRun).map(\.weekday))
        let liftDay = result.placements.first { $0.loadsLowerBody }?.weekday
        XCTAssertNotNil(liftDay)
        XCTAssertFalse(hardDays.contains(liftDay!))
        XCTAssertEqual(WeekScheduler.violations(result.placements, days: days, doubleDays: 1), [])
    }

    func testUnplaceableLowerLiftIsDroppedWithExplanation() {
        // Only Saturday and Sunday: Sunday is the long run, Saturday is the day before it.
        let days: [Weekday] = [.saturday, .sunday]
        let result = WeekScheduler.schedule(days: days, doubleDays: 1, runs: [.long], lifts: [lower])
        XCTAssertFalse(result.placements.contains { $0.loadsLowerBody })
        XCTAssertEqual(result.notes.count, 1)
        XCTAssertEqual(WeekScheduler.violations(result.placements, days: days, doubleDays: 1), [])
    }

    func testOnlyTrainingDaysAreUsed() {
        let days: [Weekday] = [.tuesday, .thursday, .saturday]
        let result = WeekScheduler.schedule(days: days, doubleDays: 0, runs: [.long, .easy], lifts: [upper])
        XCTAssertTrue(result.placements.allSatisfy { days.contains($0.weekday) })
    }

    /// Exhaustive check: for every combination of training days, double days, goal and
    /// level, the generated week obeys all interference and rest rules.
    func testAllCombinationsObeyRules() {
        for days in TestSupport.daySubsets() {
            for doubles in 0...2 {
                for goal in TrainingGoal.allCases {
                    for level in ExperienceLevel.allCases {
                        let profile = TestSupport.profile(running: level, goal: goal, days: days, doubles: doubles)
                        for phase in [TrainingPhase.base, .build] {
                            let week = WeekTarget(index: 0, startDate: TestSupport.monday, phase: phase, weekInPhase: 0,
                                                  isRecoveryWeek: false, runVolumeMeters: 30000)
                            let mix = MixBuilder.build(profile: profile, week: week, templates: templates)
                            let result = WeekScheduler.schedule(days: mix.trainingDays, doubleDays: mix.doubleDays,
                                                                runs: mix.runs, lifts: mix.lifts,
                                                                prioritiseLifts: !goal.isRunningFocused && goal != .balancedHybrid)
                            let problems = WeekScheduler.violations(result.placements, days: mix.trainingDays, doubleDays: mix.doubleDays)
                            XCTAssertEqual(problems, [], "\(days.map(\.shortName)) doubles \(doubles) \(goal) \(level) \(phase)")
                            if !problems.isEmpty { return }
                        }
                    }
                }
            }
        }
    }

    func testSevenDaysKeepsARestDay() {
        let profile = TestSupport.profile(days: Weekday.allCases, doubles: 0)
        let week = WeekTarget(index: 0, startDate: TestSupport.monday, phase: .build, weekInPhase: 0, isRecoveryWeek: false, runVolumeMeters: 30000)
        let mix = MixBuilder.build(profile: profile, week: week, templates: templates)
        XCTAssertEqual(mix.trainingDays.count, 6)
        XCTAssertFalse(mix.notes.isEmpty)
    }

    func testBaseWeeksHaveNoIntervals() {
        let profile = TestSupport.profile(running: .advanced, goal: .faster10k, days: [.monday, .tuesday, .wednesday, .thursday, .saturday, .sunday])
        let week = WeekTarget(index: 0, startDate: TestSupport.monday, phase: .base, weekInPhase: 0, isRecoveryWeek: false, runVolumeMeters: 40000)
        let mix = MixBuilder.build(profile: profile, week: week, templates: templates)
        XCTAssertFalse(mix.runs.contains(.intervals))
        XCTAssertTrue(mix.runs.contains(.tempo))
        XCTAssertTrue(mix.runs.contains(.long))
    }

    // MARK: Gym first, same muscles never back to back

    private func split(_ code: String) -> [StrengthSessionTemplate] {
        templates.programmes.strength!.split(code)!.days
    }

    private func assertNoSameMuscleBackToBack(_ placements: [Placement], file: StaticString = #filePath, line: UInt = #line) {
        let lifts = placements.compactMap { p -> (Weekday, StrengthSessionTemplate)? in
            if case .lift(let t) = p.item { return (p.weekday, t) }
            return nil
        }
        for (i, a) in lifts.enumerated() {
            for b in lifts[(i + 1)...] where a.0.circularDistance(to: b.0) == 1 {
                XCTAssertFalse(a.1.sharesMuscles(with: b.1), "\(a.1.name) (\(a.0.shortName)) and \(b.1.name) (\(b.0.shortName)) are back to back",
                               file: file, line: line)
            }
        }
    }

    func testPushAndUpperAreNotBackToBack() {
        let lifts = split("pplUpperArms")
        XCTAssertEqual(lifts.count, 5)
        let push = lifts[0], upper = lifts[3], arms = lifts[4]
        XCTAssertTrue(push.sharesMuscles(with: upper))
        XCTAssertTrue(arms.sharesMuscles(with: upper))
        XCTAssertFalse(push.sharesMuscles(with: lifts[1]), "Push and Pull can go on consecutive days")

        let days = Weekday.allCases.filter { $0 != .friday }
        let result = WeekScheduler.schedule(days: days, doubleDays: 3, runs: [.long, .tempo, .easy, .easy], lifts: lifts,
                                            prioritiseLifts: true)
        XCTAssertEqual(result.placements.filter { if case .lift = $0.item { return true }; return false }.count, 5)
        assertNoSameMuscleBackToBack(result.placements)
        XCTAssertEqual(WeekScheduler.violations(result.placements, days: days, doubleDays: 3), [])
    }

    func testFourDaySplitsAvoidOverlapWhenThereIsRoom() {
        for code in ["pplUpper", "upperLower", "ppl"] {
            let lifts = split(code)
            let result = WeekScheduler.schedule(days: Weekday.allCases.filter { $0 != .friday }, doubleDays: 2,
                                                runs: [.long, .intervals, .easy], lifts: lifts, prioritiseLifts: true)
            assertNoSameMuscleBackToBack(result.placements)
        }
    }

    func testLongRunOnChosenDay() {
        let days: [Weekday] = [.tuesday, .thursday, .saturday, .sunday]
        let result = WeekScheduler.schedule(days: days, doubleDays: 0, runs: [.long, .tempo, .easy], lifts: [upper],
                                            longRunDay: .saturday)
        XCTAssertEqual(result.placements.first { $0.item == .run(.long) }?.weekday, .saturday)
        XCTAssertEqual(WeekScheduler.violations(result.placements, days: days, doubleDays: 0), [])
    }

    func testRunningGoalsKeepTheirHardRunsWithGymFirst() {
        let days: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .saturday, .sunday]
        let result = WeekScheduler.schedule(days: days, doubleDays: 1, runs: [.long, .intervals, .tempo, .easy], lifts: [lower, upper])
        XCTAssertEqual(result.placements.filter(\.isHardRun).count, 3, "\(result.notes)")
        XCTAssertEqual(result.placements.filter { if case .lift = $0.item { return true }; return false }.count, 2)
    }
}

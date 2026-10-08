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

    func testHardDaysHardWhenDoublesAllowed() {
        // With a double available, the lower-body lift pairs with the quality run (after it).
        let days: [Weekday] = [.monday, .tuesday, .thursday, .saturday, .sunday]
        let result = WeekScheduler.schedule(days: days, doubleDays: 1, runs: [.long, .intervals, .easy, .easy], lifts: [lower])
        let intervals = result.placements.first { $0.item == .run(.intervals) }
        let lift = result.placements.first { $0.loadsLowerBody }
        XCTAssertEqual(intervals?.weekday, lift?.weekday)
        XCTAssertEqual(intervals?.slot, .morning)
        XCTAssertEqual(lift?.slot, .evening)
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
}

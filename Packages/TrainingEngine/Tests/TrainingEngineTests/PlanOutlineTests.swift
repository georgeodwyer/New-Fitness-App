import XCTest
@testable import TrainingEngine

final class PlanOutlineTests: XCTestCase {
    private let generator = TestSupport.generator

    func testEventPlanPhases() {
        // Event on the Sunday of week 16.
        let event = TestSupport.calendar.date(byAdding: .day, value: 15 * 7 + 6, to: TestSupport.monday)!
        let outline = generator.makeOutline(for: TestSupport.profile(goal: .halfMarathon, event: event), startingOn: TestSupport.monday)
        XCTAssertEqual(outline.weeks.count, 16)
        XCTAssertEqual(outline.weeks.first?.phase, .base)
        XCTAssertEqual(outline.blocks.map(\.phase), [.base, .build, .peak, .taper])
        XCTAssertEqual(outline.blocks.last?.weekCount, 2, "Half marathon tapers for two weeks")
        XCTAssertEqual(outline.blocks.first(where: { $0.phase == .peak })?.weekCount, 2)
    }

    func testShortEventSkipsBase() {
        let event = TestSupport.calendar.date(byAdding: .day, value: 2 * 7 + 5, to: TestSupport.monday)!
        let outline = generator.makeOutline(for: TestSupport.profile(goal: .first5k, event: event), startingOn: TestSupport.monday)
        XCTAssertEqual(outline.weeks.count, 3)
        XCTAssertFalse(outline.weeks.contains { $0.phase == .base })
        XCTAssertEqual(outline.weeks.last?.phase, .taper)
    }

    func testNoEventUsesRollingBlock() {
        let outline = generator.makeOutline(for: TestSupport.profile(goal: .balancedHybrid), startingOn: TestSupport.monday)
        XCTAssertEqual(outline.weeks.count, 12)
        XCTAssertNil(outline.eventDate)
        XCTAssertEqual(outline.blocks.map(\.phase), [.base, .build])
    }

    func testPastEventIsIgnored() {
        let past = TestSupport.date(2026, 1, 1)
        let outline = generator.makeOutline(for: TestSupport.profile(event: past), startingOn: TestSupport.monday)
        XCTAssertNil(outline.eventDate)
    }

    /// The 10% rule: no week's volume exceeds the last full (non-recovery) week by more than 10%.
    func testVolumeIncreasesAreCappedAtTenPercent() {
        let event = TestSupport.calendar.date(byAdding: .day, value: 25 * 7, to: TestSupport.monday)!
        for goal in TrainingGoal.allCases {
            for level in ExperienceLevel.allCases {
                for eventDate in [nil, event] {
                    let profile = TestSupport.profile(running: level, goal: goal, event: eventDate)
                    let outline = generator.makeOutline(for: profile, startingOn: TestSupport.monday)
                    var lastFull = outline.weeks[0].runVolumeMeters
                    for week in outline.weeks.dropFirst() {
                        XCTAssertLessThanOrEqual(week.runVolumeMeters, lastFull * 1.10 + 0.001,
                                                 "\(goal) \(level) week \(week.index) jumps too much")
                        if !week.isRecoveryWeek && week.phase != .taper { lastFull = week.runVolumeMeters }
                    }
                }
            }
        }
    }

    func testRecoveryWeeksEveryFourthWeek() {
        let outline = generator.makeOutline(for: TestSupport.profile(goal: .balancedHybrid), startingOn: TestSupport.monday)
        let recoveryIndices = outline.weeks.filter(\.isRecoveryWeek).map(\.index)
        XCTAssertEqual(recoveryIndices, [3, 7, 11])
        XCTAssertLessThan(outline.weeks[3].runVolumeMeters, outline.weeks[2].runVolumeMeters)
    }

    func testTaperReducesVolumeTowardsRaceWeek() {
        let event = TestSupport.calendar.date(byAdding: .day, value: 17 * 7 + 6, to: TestSupport.monday)!
        let outline = generator.makeOutline(for: TestSupport.profile(goal: .marathon, event: event), startingOn: TestSupport.monday)
        let taper = outline.weeks.filter { $0.phase == .taper }
        XCTAssertEqual(taper.count, 3)
        let peakVolume = outline.weeks.filter { $0.phase == .peak }.map(\.runVolumeMeters).max() ?? 0
        XCTAssertLessThan(taper[0].runVolumeMeters, peakVolume)
        XCTAssertLessThan(taper[1].runVolumeMeters, taper[0].runVolumeMeters)
        XCTAssertLessThan(taper[2].runVolumeMeters, taper[1].runVolumeMeters)
    }

    func testVolumeNeverExceedsGoalPeak() {
        let rules = TestSupport.templates.rules
        let profile = TestSupport.profile(running: .advanced, goal: .first5k, days: Weekday.allCases, doubles: 2)
        let outline = generator.makeOutline(for: profile, startingOn: TestSupport.monday)
        let peak = rules.peakVolumeMeters["first5k"]!["advanced"]!
        XCTAssertTrue(outline.weeks.allSatisfy { $0.runVolumeMeters <= peak + 0.001 })
    }
}

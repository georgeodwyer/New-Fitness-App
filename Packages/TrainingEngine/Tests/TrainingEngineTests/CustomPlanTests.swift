import XCTest
@testable import TrainingEngine

final class CustomPlanTests: XCTestCase {
    private let generator = TestSupport.generator
    private let calendar = TestSupport.calendar

    private func plan(weeks: Int = 12, race: Bool = true) -> CustomPlan {
        let raceDate = calendar.date(byAdding: .day, value: 7 * (weeks - 1) + 6, to: TestSupport.monday)!
        let gym = [GymTemplateItem(exerciseId: "barbell-bench-press", name: "Bench Press", sets: 4, repsLow: 6, repsHigh: 8)]
        return CustomPlan(name: "Test", weeks: weeks, startDate: TestSupport.monday,
                          raceMeters: race ? 21097.5 : nil, raceDate: race ? raceDate : nil, items: [
                            .init(weekday: .monday, activity: .gymWorkout(name: "Push", exercises: gym)),
                            .init(weekday: .tuesday, activity: .run(.intervals, meters: 8000)),
                            .init(weekday: .wednesday, activity: .run(.easy, meters: 7000)),
                            .init(weekday: .friday, activity: .gymSession("lowerA")),
                            .init(weekday: .sunday, activity: .run(.long, meters: 14000))
                          ])
    }

    func testWeeksBuildWithEasierWeeksAndATaper() {
        let custom = plan()
        XCTAssertEqual(custom.weekKinds[3], .easier)
        XCTAssertEqual(custom.weekKinds[10], .taper)
        XCTAssertEqual(custom.weekKinds[11], .taper)
        let long = custom.volumeFactors(long: true)
        XCTAssertGreaterThan(long[2], long[1])
        XCTAssertLessThan(long[3], long[2], "Easier week is lighter")
        XCTAssertLessThan(long[11], long[10], "Taper steps down")
        // Never more than 10% a week, even if asked for more.
        var greedy = custom
        greedy.longRunGrowth = 0.3
        let factors = greedy.volumeFactors(long: true)
        XCTAssertLessThanOrEqual(factors[1] / factors[0], 1.1001)
    }

    func testGeneratesTheTypicalWeekAndTheRace() throws {
        let custom = plan()
        let profile = TestSupport.profile(goal: .halfMarathon)
        let outline = generator.makeOutline(for: custom)
        XCTAssertEqual(outline.weeks.count, 12)
        XCTAssertEqual(outline.customPlan, custom)

        let first = try XCTUnwrap(generator.generateWeek(0, outline: outline, profile: profile))
        XCTAssertEqual(first.sessions.count, 5)
        XCTAssertTrue(first.sessions.contains { $0.title == "Push" && $0.strength?.exercises.first?.sets == 4 })
        let longFirst = try XCTUnwrap(first.sessions.first { $0.kind == .run(.long) }?.estimatedDistanceMeters)

        let third = try XCTUnwrap(generator.generateWeek(2, outline: outline, profile: profile))
        let longThird = try XCTUnwrap(third.sessions.first { $0.kind == .run(.long) }?.estimatedDistanceMeters)
        XCTAssertGreaterThan(longThird, longFirst, "The long run builds")

        let last = try XCTUnwrap(generator.generateWeek(11, outline: outline, profile: profile))
        XCTAssertTrue(last.sessions.contains { $0.title == "Race day" })
        XCTAssertFalse(last.sessions.contains { $0.kind == .run(.long) }, "The race replaces Sunday's long run")
    }
}

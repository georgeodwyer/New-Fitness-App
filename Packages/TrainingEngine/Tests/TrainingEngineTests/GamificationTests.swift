import XCTest
@testable import TrainingEngine

final class GamificationTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private let monday = TestSupport.monday   // 5 Oct 2026

    private func at(_ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(byAdding: .hour, value: day * 24 + hour, to: monday)!
    }

    func testPointsFavourFollowingThePlan() {
        // Week 1: two planned sessions done (load 300 and 600 → 30 + 60 capped).
        let activities = [ActivityRecord(start: at(0), durationSeconds: 2700, kind: .run, load: 300, distanceMeters: 7000),
                          ActivityRecord(start: at(2), durationSeconds: 3600, kind: .gym, load: 900)]
        let planned = [PlannedRecord(date: at(0), completed: true), PlannedRecord(date: at(2), completed: true)]
        let weeks = Points.weeks(activities, planned: planned, now: at(8), calendar: calendar)
        XCTAssertEqual(weeks.count, 1)
        let week = weeks[0]
        XCTAssertEqual(week.load, 30 + 60, "A day's load points are capped at 60")
        XCTAssertEqual(week.planned, 40)
        XCTAssertEqual(week.fullWeek, 50)
        XCTAssertEqual(week.streak, 5)
        XCTAssertEqual(week.total, 185)
    }

    func testStreakBonusGrowsAndCaps() {
        let activities = (0..<12).map { ActivityRecord(start: at($0 * 7), durationSeconds: 1800, kind: .run, load: 100, distanceMeters: 5000) }
        let weeks = Points.weeks(activities, planned: [], now: at(90), calendar: calendar)
        XCTAssertEqual(weeks.map(\.streak).prefix(3), [5, 10, 15])
        XCTAssertEqual(weeks.last?.streak, 50, "Capped at 50")
    }

    func testLevels() {
        XCTAssertEqual(Level(xp: 0).number, 1)
        XCTAssertEqual(Level(xp: 99).number, 1)
        XCTAssertEqual(Level(xp: 100).number, 2)
        XCTAssertEqual(Level(xp: 100).forNext, 107)
        XCTAssertEqual(Level(xp: 10_000_000).number, Level.maximum)
        XCTAssertNil(Level(xp: 10_000_000).forNext)
    }

    func testBadgeTiers() {
        let stats = AchievementStats(runs: 500)   // runs levels: 1, 10, 25, 50, 100, 250, 500
        let runs = Achievements.make(stats, calendar: calendar).first { $0.kind == .runs }!
        XCTAssertEqual(runs.tier, .platinum)
        let few = Achievements.make(AchievementStats(runs: 10), calendar: calendar).first { $0.kind == .runs }!
        XCTAssertEqual(few.tier, .bronze)
        let mid = Achievements.make(AchievementStats(runs: 50), calendar: calendar).first { $0.kind == .runs }!
        XCTAssertEqual(mid.tier, .silver)
    }

    func testFunBadges() {
        let earlyRuns = (0..<5).map { ActivityRecord(start: at($0, 6), durationSeconds: 1800, kind: .run, load: 100, distanceMeters: 5000) }
        let hybrid = ActivityRecord(start: at(0, 18), durationSeconds: 3600, kind: .gym, load: 300)
        let negative = ActivityRecord(start: at(10), durationSeconds: 1500, kind: .run, load: 200, distanceMeters: 5000,
                                      splitSeconds: [310, 305, 300, 290, 285])
        let badges = FunBadges.make(earlyRuns + [hybrid, negative], recordDates: [], calendar: calendar)
        func badge(_ id: String) -> FunBadge { badges.first { $0.id == id }! }
        XCTAssertTrue(badge("earlyBird").earned)
        XCTAssertTrue(badge("hybridDay").earned)
        XCTAssertTrue(badge("negativeSplit").earned)
        XCTAssertFalse(badge("marathoner").earned)
        XCTAssertTrue(badge("marathoner").isHidden)
        XCTAssertFalse(badge("nightOwl").earned)
    }

    func testMonthlyChallenges() {
        let challenges = MonthlyChallenges.forMonth(containing: monday, calendar: calendar)
        XCTAssertEqual(challenges.count, 4)
        XCTAssertEqual(challenges.first?.id, "2026-10-runKilometres")
        let km = challenges[0]
        let runs = [ActivityRecord(start: at(1), durationSeconds: 3000, kind: .run, load: 200, distanceMeters: 10_500),
                    ActivityRecord(start: at(40), durationSeconds: 3000, kind: .run, load: 200, distanceMeters: 8000)]  // November
        XCTAssertEqual(MonthlyChallenges.value(km, activities: runs, planned: [], calendar: calendar), 10.5)
        let planned = [PlannedRecord(date: at(1), completed: true), PlannedRecord(date: at(3), completed: false)]
        XCTAssertEqual(MonthlyChallenges.value(challenges[3], activities: [], planned: planned, calendar: calendar), 50)
    }

    func testStatistics() {
        let activities = [ActivityRecord(start: at(0), durationSeconds: 1800, kind: .run, load: 120, distanceMeters: 5000, runType: "easy", cadence: 168),
                          ActivityRecord(start: at(2), durationSeconds: 3600, kind: .gym, load: 360, sets: 16),
                          ActivityRecord(start: at(7), durationSeconds: 1500, kind: .run, load: 120, distanceMeters: 5000, runType: "easy", cadence: 172)]
        let weekly = TrainingStats.weekly(activities, weeks: 2, now: at(8), calendar: calendar)
        XCTAssertEqual(weekly.map(\.totals.runs), [1, 1])
        XCTAssertEqual(weekly.first?.totals.gymSets, 16)
        let pace = TrainingStats.paceTrend(activities, runType: "easy", weeks: 2, now: at(8), calendar: calendar)
        XCTAssertEqual(pace.map(\.value), [360, 300])
        XCTAssertEqual(TrainingStats.cadenceTrend(activities, weeks: 2, now: at(8), calendar: calendar).map(\.value), [168, 172])
        let heat = TrainingStats.heatmap(activities, days: 14, now: at(8), calendar: calendar)
        XCTAssertEqual(heat.count, 14)
        XCTAssertEqual(heat.filter { $0.level > 0 }.count, 3)
        XCTAssertEqual(TrainingStats.averageRunsPerWeek(activities, weeks: 2, now: at(14), calendar: calendar), 1)
    }
}

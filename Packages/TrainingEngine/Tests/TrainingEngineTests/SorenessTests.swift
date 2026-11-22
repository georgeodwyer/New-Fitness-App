import XCTest
@testable import TrainingEngine

/// Sore legs or upper body change only the sessions that work them (check-in 1–2 out of 5).
final class SorenessTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private let day = TestSupport.monday
    private var context: Rebalancer.Context {
        Rebalancer.Context(trainingDays: Weekday.allCases, zones: PaceZones(race: RaceResult(distanceMeters: 5000, timeSeconds: 22 * 60)),
                           units: .metric, calendar: calendar, today: day)
    }

    private func gym() -> WeekSession {
        func exercise(_ id: String, _ sets: Int) -> ExercisePrescription {
            ExercisePrescription(exerciseId: id, name: id, role: .main, sets: sets, repRange: RepRange(6, 8), weightKg: 50, restSeconds: 120)
        }
        return WeekSession(id: UUID(), date: day, slot: .evening, kind: .strength(.fullBody), isKey: false, title: "Full body A",
                           durationMinutes: 50, effort: 6,
                           strength: StrengthPrescription(exercises: [exercise("squat", 4), exercise("bench", 4), exercise("row", 3)]))
    }

    private let region: (String) -> BodyRegion? = { ["squat": .lower, "bench": .upper, "row": .upper][$0] }

    func testSoreAreasFromTheCheckIn() {
        // Stored soreness 4–5 is "sore" (shown as 2 or 1 out of 5).
        XCTAssertEqual(Rebalancer.soreAreas(RecoveryCheckIn(sleep: 3, soreness: 2, energy: 3, legSoreness: 4)), [.legs])
        XCTAssertEqual(Rebalancer.soreAreas(RecoveryCheckIn(sleep: 3, soreness: 5, energy: 3, legSoreness: 1)), [.upper])
        XCTAssertEqual(Rebalancer.soreAreas(RecoveryCheckIn(sleep: 3, soreness: 3, energy: 3, legSoreness: 3)), [])
        XCTAssertEqual(Rebalancer.soreAreas(RecoveryCheckIn(sleep: 3, soreness: 4, energy: 3)), [.legs, .upper], "Older check-ins: one answer for both")
    }

    func testRunsIgnoreUpperBodySoreness() throws {
        let sore = RecoveryCheckIn(sleep: 3, soreness: 5, energy: 3, legSoreness: 1)
        let overall = try XCTUnwrap(RecoveryScore.make(hrv: nil, restingHeartRate: nil, sleepHours: nil, checkIn: sore))
        let forRuns = try XCTUnwrap(RecoveryScore.make(hrv: nil, restingHeartRate: nil, sleepHours: nil, checkIn: Rebalancer.forRuns(sore)))
        XCTAssertLessThanOrEqual(overall.score, 55, "Very sore upper body caps the overall score")
        XCTAssertGreaterThan(forRuns.score, 67, "But a run isn't held back by it")
    }

    func testSoreLegsOfferAnEasyRunForAHardOne() throws {
        let intervals = WeekSession(id: UUID(), date: day, slot: .morning, kind: .run(.intervals), isKey: false, title: "Intervals",
                                    durationMinutes: 55, effort: 8)
        let option = try XCTUnwrap(Rebalancer.easyRunForSoreLegs(intervals, legs: 4, context: context))
        XCTAssertEqual(option.replacement.kind, .run(.easy))
        XCTAssertTrue(option.explanation.contains("legs are sore today (2/5)"))
        let easy = WeekSession(id: UUID(), date: day, slot: .morning, kind: .run(.easy), isKey: false, title: "Easy Run",
                               durationMinutes: 40, effort: 3)
        XCTAssertNil(Rebalancer.easyRunForSoreLegs(easy, legs: 5, context: context), "Already easy: only a move is offered")
    }

    func testSoreLegsCutOnlyLowerBodySets() throws {
        let checkIn = RecoveryCheckIn(sleep: 3, soreness: 1, energy: 3, legSoreness: 4)
        let option = try XCTUnwrap(Rebalancer.fewerSetsForSoreness(gym(), areas: [.legs], region: region, recovery: nil, checkIn: checkIn))
        let sets = option.replacement.strength?.exercises.map(\.sets)
        XCTAssertEqual(sets, [3, 4, 3], "Squat 4 → 3; bench and row as planned")
        XCTAssertTrue(option.explanation.contains("lower-body"))
        // A session without leg work isn't touched by sore legs.
        var upperOnly = gym()
        upperOnly.strength?.exercises.removeFirst()
        XCTAssertNil(Rebalancer.fewerSetsForSoreness(upperOnly, areas: [.legs], region: region, recovery: nil, checkIn: checkIn))
        XCTAssertEqual(Rebalancer.areasWorked(upperOnly, region: region), [.upper])
    }
}

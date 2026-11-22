import XCTest
@testable import TrainingEngine

final class HealthRunMatchTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private let morning = Date(timeIntervalSince1970: 1_800_000_000)

    private func run(_ minutesAfter: Double, km: Double, id: UUID = UUID()) -> ExternalWorkout {
        let start = morning.addingTimeInterval(minutesAfter * 60)
        return ExternalWorkout(id: id, start: start, end: start.addingTimeInterval(30 * 60), kind: .run, name: "Indoor Run",
                               distanceMeters: km * 1000)
    }

    func testATreadmillRunIsOfferedForThatDaysPlannedRun() throws {
        let easy = HealthRunMatch.Planned(id: UUID(), date: morning, meters: 5000)
        let long = HealthRunMatch.Planned(id: UUID(), date: morning, meters: 12_000)
        let treadmill = run(60, km: 5.2)
        let suggestions = HealthRunMatch.suggestions(external: [treadmill], recorded: [], planned: [long, easy], dismissed: [],
                                                     now: morning.addingTimeInterval(3 * 3600), calendar: calendar)
        XCTAssertEqual(suggestions.map(\.plannedId), [easy.id], "The closest planned run in distance")
    }

    func testNotOfferedWhenAlreadyInKinetixDismissedOrAnotherDay() {
        let planned = HealthRunMatch.Planned(id: UUID(), date: morning, meters: 5000)
        let treadmill = run(60, km: 5)
        let later = morning.addingTimeInterval(3 * 3600)
        let recorded = DateInterval(start: treadmill.start, duration: 30 * 60)
        XCTAssertTrue(HealthRunMatch.suggestions(external: [treadmill], recorded: [recorded], planned: [planned], dismissed: [],
                                                 now: later, calendar: calendar).isEmpty)
        XCTAssertTrue(HealthRunMatch.suggestions(external: [treadmill], recorded: [], planned: [planned], dismissed: [treadmill.id],
                                                 now: later, calendar: calendar).isEmpty)
        let tomorrow = HealthRunMatch.Planned(id: UUID(), date: morning.addingTimeInterval(86_400), meters: 5000)
        XCTAssertTrue(HealthRunMatch.suggestions(external: [treadmill], recorded: [], planned: [tomorrow], dismissed: [],
                                                 now: later, calendar: calendar).isEmpty)
    }
}

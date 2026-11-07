import XCTest
import SwiftData
import TrainingEngine
@testable import Kinetix

@MainActor
final class FunctionalAppTests: XCTestCase {
    private var containers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try Persistence.makeContainer(inMemory: true)
        containers.append(container)
        return container.mainContext
    }

    private let workout = FunctionalWorkout(name: "Engine", format: .rounds(3), stations: [
        FunctionalStation(kind: .run, target: .seconds(60), pace: .fixed(.single(Pace(secondsPerKm: 240)))),
        FunctionalStation(kind: .wallBalls, target: .reps(20), weightKg: 6)
    ])

    func testSavedFunctionalWorkoutsSync() throws {
        let context = try makeContext()
        let template = FunctionalTemplateModel(workout: workout)
        context.insert(template)
        XCTAssertEqual(template.id, workout.id)
        let record = try template.syncRecord()
        XCTAssertEqual(record.type, "functionalTemplate")
        let copy = FunctionalTemplateModel.makeForSync(id: template.id)
        context.insert(copy)
        try copy.apply(record, context: context)
        XCTAssertEqual(copy.workout, workout)
    }

    func testFunctionalSessionSavesItsSplitsAndSyncsThem() throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var session = FunctionalSession(workout: workout, startedAt: start)
        session.tick(at: start.addingTimeInterval(61), meters: 250)   // the timed run moves on by itself
        XCTAssertEqual(session.station?.kind, .wallBalls)
        session.next(at: start.addingTimeInterval(110))
        let log = StrengthLogModel(plannedSessionId: nil, startedAt: start)
        log.functionalData = StoredJSON.encode(FunctionalRecord(session: session))
        context.insert(log)
        XCTAssertTrue(log.isFunctional)
        XCTAssertEqual(log.functional?.splits.count, 2)
        XCTAssertEqual(log.functional?.splits.first?.meters, 250)
        XCTAssertEqual(log.functional?.splits.first?.seconds, 60)

        let copy = StrengthLogModel.makeForSync(id: UUID())
        context.insert(copy)
        try copy.apply(try log.syncRecord(), context: context)
        XCTAssertEqual(copy.functional, log.functional)
    }
}

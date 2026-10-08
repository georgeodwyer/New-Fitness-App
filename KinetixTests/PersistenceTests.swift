import XCTest
import SwiftData
import TrainingEngine
@testable import Kinetix

@MainActor
final class PersistenceTests: XCTestCase {
    func testProfileRoundTrip() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.insert(UserProfileModel(profile: SampleData.profile))
        try context.save()

        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<UserProfileModel>()).first)
        XCTAssertEqual(stored.profile, SampleData.profile)
    }

    func testEditingMarksRecordForSync() throws {
        let model = UserProfileModel(profile: SampleData.profile, now: Date(timeIntervalSince1970: 0))
        model.needsSync = false
        var updated = model.profile
        updated.units = .imperial
        model.profile = updated
        XCTAssertTrue(model.needsSync)
        XCTAssertGreaterThan(model.updatedAt, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(model.units, .imperial)
    }

    func testSeedCreatesSessionsWithStructure() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        SampleData.seed(into: context)

        let sessions = try context.fetch(FetchDescriptor<PlannedSessionModel>())
        XCTAssertFalse(sessions.isEmpty)
        let tempo = try XCTUnwrap(sessions.first { $0.kind == .run(.tempo) })
        XCTAssertEqual(tempo.runStructure?.segments.count, 3)
        XCTAssertNotNil(tempo.plan)
    }

    func testSoftDelete() {
        let session = PlannedSessionModel(date: .now, slot: .morning, kind: .mobility, isKey: false, plannedDurationMinutes: 20, plannedEffort: 2)
        session.needsSync = false
        session.softDelete()
        XCTAssertTrue(session.isSoftDeleted)
        XCTAssertTrue(session.needsSync)
    }
}

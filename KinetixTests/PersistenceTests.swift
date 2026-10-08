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

    func testSoftDelete() {
        let session = PlannedSessionModel(date: .now, slot: .morning, kind: .mobility, isKey: false, plannedDurationMinutes: 20, plannedEffort: 2)
        session.needsSync = false
        session.softDelete()
        XCTAssertTrue(session.isSoftDeleted)
        XCTAssertTrue(session.needsSync)
    }
}

@MainActor
final class PlanServiceTests: XCTestCase {
    /// Monday 5 October 2026, 08:00.
    private let monday = Calendar.kinetix.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 8))!

    func testCreatePlanStoresOutlineSessionsAndWeights() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let plan = PlanService.createPlan(for: SampleData.profile, in: context, now: monday)

        XCTAssertNotNil(plan.outline)
        XCTAssertGreaterThanOrEqual(plan.generatedWeekCount, 2, "About two weeks of sessions are generated up front")
        let sessions = try context.fetch(FetchDescriptor<PlannedSessionModel>())
        XCTAssertFalse(sessions.isEmpty)
        XCTAssertTrue(sessions.allSatisfy { !$0.title.isEmpty && !$0.summary.isEmpty })
        XCTAssertTrue(sessions.contains { $0.runStructure != nil })
        XCTAssertTrue(sessions.contains { $0.strengthPrescription != nil })

        let states = try context.fetch(FetchDescriptor<ExerciseStateModel>())
        XCTAssertFalse(states.isEmpty, "Starting weights are recorded for progression")
        XCTAssertEqual(Set(states.map(\.progressionKey)).count, states.count, "One state per exercise and role")
    }

    func testRefreshExtendsHorizon() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.insert(UserProfileModel(profile: SampleData.profile))
        let plan = PlanService.createPlan(for: SampleData.profile, in: context, now: monday)
        let before = plan.generatedWeekCount

        let threeWeeksLater = Calendar.kinetix.date(byAdding: .day, value: 21, to: monday)!
        PlanService.refresh(in: context, now: threeWeeksLater)
        XCTAssertGreaterThan(plan.generatedWeekCount, before)
    }

    func testRegeneratingRemovesOldFutureSessions() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let first = PlanService.createPlan(for: SampleData.profile, in: context, now: monday)
        let second = PlanService.createPlan(for: SampleData.profile, in: context, now: monday)

        XCTAssertFalse(first.isActive)
        XCTAssertTrue(second.isActive)
        XCTAssertTrue(first.sessions.allSatisfy(\.isSoftDeleted))
        XCTAssertTrue(second.sessions.allSatisfy { !$0.isSoftDeleted })
    }
}

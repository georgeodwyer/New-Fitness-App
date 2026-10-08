import XCTest
import SwiftData
import TrainingEngine
@testable import Kinetix

@MainActor
final class StrengthServiceTests: XCTestCase {
    private let monday = Calendar.kinetix.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 8))!

    private func makeContext() throws -> ModelContext {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        // Keep the container alive for the test's duration.
        containers.append(container)
        context.insert(UserProfileModel(profile: SampleData.profile))
        PlanService.createPlan(for: SampleData.profile, in: context, now: monday)
        return context
    }
    private var containers: [ModelContainer] = []

    private func strengthSessions(in context: ModelContext) throws -> [PlannedSessionModel] {
        try context.fetch(FetchDescriptor<PlannedSessionModel>(sortBy: [SortDescriptor(\.date)]))
            .filter { $0.strengthPrescription != nil && !$0.isSoftDeleted }
    }

    func testStartPrefillsSetsAndResumes() throws {
        let context = try makeContext()
        let session = try XCTUnwrap(strengthSessions(in: context).first)
        let log = StrengthService.startOrResume(session, in: context, now: monday)
        let expectedSets = session.strengthPrescription!.exercises.reduce(0) { $0 + $1.sets }
        XCTAssertEqual(log.sets.count, expectedSets)
        XCTAssertTrue(log.sets.allSatisfy { $0.actualReps == $0.repRangeUpper && !$0.isCompleted })

        let resumed = StrengthService.startOrResume(session, in: context, now: monday)
        XCTAssertEqual(resumed.id, log.id, "An unfinished workout is resumed, not duplicated")
    }

    func testFinishingAtTopOfRangeIncreasesWeightsAndUpdatesFutureSessions() throws {
        let context = try makeContext()
        let sessions = try strengthSessions(in: context)
        let session = try XCTUnwrap(sessions.first)
        let log = StrengthService.startOrResume(session, in: context, now: monday)
        for set in log.sets { set.completedAt = monday; set.rpe = 8 }

        let main = try XCTUnwrap(log.orderedSets.first { !$0.isBodyweight && $0.progressionKey.hasSuffix(".main") })
        let before = main.actualWeightKg
        let summary = StrengthService.finish(log, planned: session, effort: 7, units: .metric, in: context,
                                             now: monday.addingTimeInterval(3600))

        XCTAssertEqual(session.status, .completed)
        XCTAssertTrue(log.isFinished)
        XCTAssertEqual(log.load, 420, accuracy: 0.01, "60 min × effort 7")
        XCTAssertTrue(summary.changes.contains { if case .increase = $0.change { return true }; return false })

        let key = main.progressionKey
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<ExerciseStateModel>(predicate: #Predicate { $0.progressionKey == key })).first)
        XCTAssertGreaterThan(state.workingWeightKg, before)
        XCTAssertNotNil(state.lastChangeReason)

        // Later sessions using the same lift now prescribe the new weight.
        let later = sessions.dropFirst().compactMap(\.strengthPrescription).flatMap(\.exercises).filter { $0.progressionKey == key }
        XCTAssertTrue(later.allSatisfy { $0.weightKg == state.workingWeightKg })

        let records = try context.fetch(FetchDescriptor<PersonalRecordModel>())
        XCTAssertFalse(records.isEmpty, "First session stores baseline bests")
        XCTAssertTrue(summary.records.isEmpty, "Nothing to beat on the first session")
    }

    func testMissedRepsHoldWeight() throws {
        let context = try makeContext()
        let session = try XCTUnwrap(strengthSessions(in: context).first)
        let log = StrengthService.startOrResume(session, in: context, now: monday)
        for set in log.sets {
            set.completedAt = monday
            set.actualReps = max(0, set.repRangeLower - 2)
        }
        let main = try XCTUnwrap(log.orderedSets.first { !$0.isBodyweight })
        let before = main.actualWeightKg
        _ = StrengthService.finish(log, planned: session, effort: 9, units: .metric, in: context, now: monday.addingTimeInterval(3000))

        let key = main.progressionKey
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<ExerciseStateModel>(predicate: #Predicate { $0.progressionKey == key })).first)
        XCTAssertEqual(state.workingWeightKg, before)
        XCTAssertEqual(state.stallCount, 1)
    }

    func testDiscardRemovesWorkout() throws {
        let context = try makeContext()
        let session = try XCTUnwrap(strengthSessions(in: context).first)
        let log = StrengthService.startOrResume(session, in: context, now: monday)
        StrengthService.discard(log, in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StrengthLogModel>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SetLogModel>()).isEmpty)
    }
}

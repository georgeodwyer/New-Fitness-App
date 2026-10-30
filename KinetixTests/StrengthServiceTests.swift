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
        // First time: the bottom of the range (reps then climb one at a time).
        XCTAssertTrue(log.sets.allSatisfy { $0.actualReps == $0.repRangeLower && !$0.isCompleted })

        let resumed = StrengthService.startOrResume(session, in: context, now: monday)
        XCTAssertEqual(resumed.id, log.id, "An unfinished workout is resumed, not duplicated")
    }

    func testRemovingASetRenumbersTheRest() throws {
        let context = try makeContext()
        let session = try XCTUnwrap(strengthSessions(in: context).first)
        let log = StrengthService.startOrResume(session, in: context, now: monday)
        let key = try XCTUnwrap(log.orderedSets.first?.progressionKey)
        let before = log.orderedSets.filter { $0.progressionKey == key }
        XCTAssertGreaterThan(before.count, 1)
        StrengthService.removeSet(before[0], from: log, in: context)
        let after = log.orderedSets.filter { $0.progressionKey == key }
        XCTAssertEqual(after.count, before.count - 1)
        XCTAssertEqual(after.map(\.setIndex), Array(0..<after.count))
    }

    func testFinishingAtTopOfRangeIncreasesWeightsAndUpdatesFutureSessions() throws {
        let context = try makeContext()
        let sessions = try strengthSessions(in: context)
        let session = try XCTUnwrap(sessions.first)
        let log = StrengthService.startOrResume(session, in: context, now: monday)
        // Every set done at the top of its range.
        for set in log.sets { set.actualReps = set.repRangeUpper; set.completedAt = monday; set.rpe = 8 }

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

    func testMarkedDoneAsPlannedCountsLikeAFullSession() throws {
        let context = try makeContext()
        let session = try XCTUnwrap(strengthSessions(in: context).first)
        let summary = StrengthService.logManual(for: session, allSetsDone: true, startedAt: monday, durationSeconds: 3600,
                                                effort: 7, units: .metric, in: context)
        let log = try XCTUnwrap(context.fetch(FetchDescriptor<StrengthLogModel>()).first)
        XCTAssertTrue(log.isManual)
        XCTAssertTrue(log.isFinished)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(log.load, 420, accuracy: 0.01, "60 min × effort 7")
        XCTAssertTrue(log.sets.allSatisfy { $0.isCompleted && $0.actualReps == $0.targetReps })
        XCTAssertFalse(summary.changes.isEmpty, "Progression runs as for a tracked session")
    }

    func testMarkedDoneNotAllOfItHoldsWeights() throws {
        let context = try makeContext()
        let session = try XCTUnwrap(strengthSessions(in: context).first)
        let before = PlanService.workingWeights(in: context)
        StrengthService.logManual(for: session, allSetsDone: false, startedAt: monday, durationSeconds: 1800,
                                  effort: 6, units: .metric, in: context)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(PlanService.workingWeights(in: context), before, "Weights stay the same")
    }
}

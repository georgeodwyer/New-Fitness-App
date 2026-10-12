import XCTest
import SwiftData
import TrainingEngine
@testable import Kinetix

@MainActor
final class HistoryTests: XCTestCase {
    private let monday = Calendar.kinetix.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 8))!
    private var containers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try Persistence.makeContainer(inMemory: true)
        containers.append(container)
        let context = container.mainContext
        context.insert(UserProfileModel(profile: SampleData.profile))
        PlanService.createPlan(for: SampleData.profile, in: context, now: monday)
        return context
    }

    private func plannedRun(in context: ModelContext) throws -> PlannedSessionModel {
        try XCTUnwrap(context.fetch(FetchDescriptor<PlannedSessionModel>()).first { $0.kind.discipline == .run && $0.runStructure != nil })
    }

    func testRunTypeIsRecorded() throws {
        let context = try makeContext()
        let planned = try plannedRun(in: context)
        let fromPlan = RunService.begin(planned: planned, title: planned.title, simulated: true, in: context, now: monday)
        guard case .run(let type) = planned.kind else { return XCTFail("Not a run") }
        XCTAssertEqual(fromPlan.runType, type)
        XCTAssertEqual(fromPlan.sourceTag, "Planned")

        let recorded = RunService.begin(planned: nil, title: "Intervals", simulated: true, recordType: .intervals, in: context, now: monday)
        XCTAssertEqual(recorded.runType, .intervals)
        XCTAssertEqual(recorded.recordType, .intervals)
        XCTAssertEqual(recorded.sourceTag, "Recorded")
        XCTAssertFalse(recorded.countsTowardsHistory, "Unfinished and simulated runs stay out of totals")
    }

    func testEditingEffortUpdatesLoad() throws {
        let context = try makeContext()
        let log = RunService.begin(planned: nil, title: "Run", simulated: false, in: context, now: monday)
        log.durationSeconds = 1800
        log.isFinished = true
        RunService.update(log, title: "Sunrise run", effort: 6, in: context)
        XCTAssertEqual(log.title, "Sunrise run")
        XCTAssertEqual(log.load, 180)
        RunService.update(log, title: "  ", effort: 4, in: context)
        XCTAssertEqual(log.title, "Sunrise run", "A blank name keeps the old one")
        XCTAssertEqual(log.load, 120)
    }

    func testDeletingARunReopensItsPlannedSession() throws {
        let context = try makeContext()
        let planned = try plannedRun(in: context)
        let log = RunService.begin(planned: planned, title: planned.title, simulated: false, in: context, now: monday)
        RunService.finish(RunEngine(structure: nil).summary(), log: log, planned: planned, effort: 4, in: context, now: monday)
        XCTAssertEqual(planned.status, .completed)

        RunService.delete(log, in: context)
        XCTAssertTrue(log.isSoftDeleted)
        XCTAssertEqual(planned.status, .planned)
        XCTAssertTrue(DashboardService.loadEntries(runs: [log], lifts: []).isEmpty, "Deleted runs leave the load")
    }

    func testDeletingAStrengthSessionRemovesItsSets() throws {
        let context = try makeContext()
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<PlannedSessionModel>()).first { $0.strengthPrescription != nil })
        let log = StrengthService.startOrResume(session, in: context, now: monday)
        _ = StrengthService.finish(log, planned: session, effort: 7, units: .metric, in: context, now: monday.addingTimeInterval(3000))
        StrengthService.update(log, title: "Legs", effort: 8, in: context)
        XCTAssertEqual(log.title, "Legs")

        StrengthService.delete(log, in: context)
        XCTAssertTrue(log.isSoftDeleted)
        XCTAssertTrue(log.sets.allSatisfy(\.isSoftDeleted))
        XCTAssertEqual(session.status, .planned)
    }

    func testSampleHistoryHasRoutesForBestEfforts() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        containers.append(container)
        SampleData.seedHistory(into: container.mainContext, now: monday)
        let runs = try container.mainContext.fetch(FetchDescriptor<RunLogModel>())
        let longest = try XCTUnwrap(runs.max { $0.distanceMeters < $1.distanceMeters })
        let efforts = RunAnalysis.bestEfforts(route: longest.route)
        XCTAssertNotNil(efforts[.fiveK])
        XCTAssertNotNil(efforts[.tenK])
        XCTAssertFalse(longest.heartRateSamples.isEmpty)
    }
}

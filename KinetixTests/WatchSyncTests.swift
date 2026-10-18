import XCTest
import SwiftData
import TrainingEngine
@testable import Kinetix

@MainActor
final class WatchSyncTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private let monday = Calendar.kinetix.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 7))!

    private func makeContext() throws -> ModelContext {
        let container = try Persistence.makeContainer(inMemory: true)
        containers.append(container)
        return container.mainContext
    }

    private func summary(minutes: Double) -> RunSummary {
        RunSummary(durationSeconds: minutes * 60, distanceMeters: minutes * 180, averagePace: Pace(secondsPerKm: 333), splits: [],
                   segments: [], timeInTargetSeconds: 0, targetedSeconds: 0, averageHeartRate: 148, maxHeartRate: 171,
                   route: [RoutePoint(latitude: 51.5, longitude: -0.16, elapsed: 0), RoutePoint(latitude: 51.51, longitude: -0.16, elapsed: minutes * 60)])
    }

    func testPlanHasTheWeeksRunsAndSavedWorkouts() throws {
        let context = try makeContext()
        PlanService.createPlan(for: SampleData.profile, in: context, now: monday)
        context.insert(RunTemplateModel(workout: CustomRunWorkout.starter(for: .tempo, zones: PaceZones(vdot: 45))))
        try context.save()

        let plan = WatchSyncService.makePlan(in: context, now: monday)
        let planned = plan.runs.filter { $0.source == .planned }
        XCTAssertFalse(planned.isEmpty)
        XCTAssertTrue(planned.allSatisfy { ($0.date ?? .distantPast) >= Calendar.kinetix.startOfDay(for: monday) })
        XCTAssertTrue(planned.contains { $0.structure != nil }, "Structured runs carry their steps and targets")
        XCTAssertEqual(plan.templates.count, 1)
        XCTAssertEqual(plan.templates.first?.recordType, "tempo")
        XCTAssertEqual(WatchPlan.decode(plan.encoded()), plan)
    }

    func testRunFromWatchIsSavedOnceAndTicksOffThePlan() throws {
        let context = try makeContext()
        PlanService.createPlan(for: SampleData.profile, in: context, now: monday)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<PlannedSessionModel>()).first { $0.kind.discipline == .run })
        let option = WatchRunOption(id: session.id, source: .planned, title: session.title, date: session.date,
                                    structure: session.runStructure, typicalEffort: 6)
        let healthId = UUID()
        let result = WatchRunResult(option: option, startedAt: session.date, finishedAt: session.date.addingTimeInterval(1800),
                                    summary: summary(minutes: 30), effort: 6, healthKitWorkoutId: healthId)

        let log = try XCTUnwrap(WatchSyncService.save(result, in: context))
        XCTAssertEqual(log.id, result.id)
        XCTAssertTrue(log.isFinished)
        XCTAssertEqual(log.plannedSessionId, session.id)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(log.healthKitWorkoutId, healthId, "Not saved to Health again")
        XCTAssertEqual(log.load, SessionLoad.srpe(durationSeconds: 1800, effort: 6), accuracy: 0.001)
        XCTAssertEqual(log.route.count, 2)
        XCTAssertNil(WatchSyncService.save(result, in: context), "Delivered twice, saved once")
        XCTAssertEqual(try context.fetch(FetchDescriptor<RunLogModel>()).count, 1)
    }

    func testFreeRunFromWatch() throws {
        let context = try makeContext()
        let result = WatchRunResult(option: .freeRun, startedAt: monday, finishedAt: monday.addingTimeInterval(1200),
                                    summary: summary(minutes: 20), effort: 4)
        let log = try XCTUnwrap(WatchSyncService.save(result, in: context))
        XCTAssertNil(log.plannedSessionId)
        XCTAssertEqual(log.recordType, .free)
        XCTAssertEqual(log.sourceTag, "Recorded")
    }
}

import XCTest
import SwiftData
import TrainingEngine
@testable import Kinetix

@MainActor
final class RunServiceTests: XCTestCase {
    func testFinishingARunStoresSummaryAndLoad() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 2_000_000)
        let structure = RunStructure(segments: [
            RunSegment(kind: .steady, length: .distance(meters: 2000),
                       targetPace: PaceRange(fastest: Pace(secondsPerKm: 300), slowest: Pace(secondsPerKm: 320)), label: "Easy run")
        ])
        let planned = PlannedSessionModel(date: start, slot: .morning, kind: .run(.easy), isKey: false,
                                          plannedDurationMinutes: 12, plannedEffort: 3, runStructure: structure)
        context.insert(planned)

        var engine = RunEngine(structure: structure)
        _ = engine.start(at: start)
        for sample in SimulatedRunner(structure: structure, driftMeters: 0, speedNoise: 0).samples(start: start, duration: 660) {
            _ = engine.addLocation(sample)
        }
        let summary = engine.summary()

        let log = RunService.begin(planned: planned, title: "Easy Run", simulated: true, in: context, now: start)
        RunService.finish(summary, log: log, planned: planned, effort: 4, in: context, now: start.addingTimeInterval(660))

        XCTAssertTrue(log.isFinished)
        XCTAssertEqual(planned.status, .completed)
        XCTAssertEqual(log.distanceMeters, summary.distanceMeters)
        XCTAssertEqual(log.load, 660 / 60 * 4, accuracy: 0.01)
        XCTAssertEqual(log.splits.count, 2)
        XCTAssertFalse(log.route.isEmpty)
        XCTAssertEqual(log.segmentResults.count, 1)
        XCTAssertNotNil(log.averagePace)
    }

    func testDiscardDeletesRun() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let log = RunService.begin(planned: nil, title: "Run", simulated: false, in: context)
        RunService.discard(log, in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<RunLogModel>()).isEmpty)
    }

    func testMarkingARunDoneCountsItWithoutRecording() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 2_000_000)
        let planned = PlannedSessionModel(date: start, slot: .morning, kind: .run(.easy), isKey: false,
                                          plannedDurationMinutes: 30, plannedEffort: 3, runStructure: nil)
        context.insert(planned)

        let log = RunService.logManual(for: planned, startedAt: start, durationSeconds: 1800, distanceMeters: 5000,
                                       effort: 4, averageHeartRate: 140, in: context)

        XCTAssertEqual(planned.status, .completed)
        XCTAssertTrue(log.isFinished)
        XCTAssertTrue(log.isLoggedByHand)
        XCTAssertEqual(log.sourceTag, "Logged by hand")
        XCTAssertEqual(log.plannedSessionId, planned.id)
        XCTAssertEqual(log.load, 30 * 4, accuracy: 0.01)
        XCTAssertEqual(log.finishedAt, start.addingTimeInterval(1800))
        XCTAssertTrue(log.route.isEmpty)
    }

    func testCanMarkDoneOnlyForTheLastWeek() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        func session(daysAgo: Int) -> PlannedSessionModel {
            PlannedSessionModel(date: now.addingTimeInterval(Double(-daysAgo) * 86_400), slot: .morning, kind: .run(.easy),
                                isKey: false, plannedDurationMinutes: 30, plannedEffort: 3, runStructure: nil)
        }
        XCTAssertTrue(session(daysAgo: 0).canMarkDone(now: now))
        XCTAssertTrue(session(daysAgo: 7).canMarkDone(now: now))
        XCTAssertFalse(session(daysAgo: 8).canMarkDone(now: now))
        XCTAssertFalse(session(daysAgo: -1).canMarkDone(now: now), "Not future sessions")
    }
}

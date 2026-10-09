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
}

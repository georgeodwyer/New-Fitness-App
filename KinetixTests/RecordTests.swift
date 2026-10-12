import XCTest
import SwiftData
import TrainingEngine
@testable import Kinetix

@MainActor
final class RecordTests: XCTestCase {
    private var containers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try Persistence.makeContainer(inMemory: true)
        containers.append(container)
        return container.mainContext
    }

    func testTemplateStoresTheWorkout() throws {
        let context = try makeContext()
        var workout = CustomRunWorkout.starter(for: .tempo, zones: PaceZones(vdot: 45))
        workout.name = "Threshold 2 × 10"
        let template = RunTemplateModel(workout: workout)
        context.insert(template)
        try context.save()

        let loaded = try XCTUnwrap(context.fetch(FetchDescriptor<RunTemplateModel>()).first)
        XCTAssertEqual(loaded.workout.name, "Threshold 2 × 10")
        XCTAssertEqual(loaded.workout.blocks, workout.blocks)
        XCTAssertEqual(loaded.workout.type, .tempo)

        workout.blocks[1].repeats = 3
        loaded.workout = workout
        XCTAssertEqual(loaded.workout.blocks[1].repeats, 3)
    }

    func testRunScreenFollowsTheCustomWorkout() throws {
        let context = try makeContext()
        let workout = CustomRunWorkout.starter(for: .intervals, zones: PaceZones(vdot: 45))
        let model = RunWorkoutModel(planned: nil, custom: workout, units: .metric, settings: nil, simulationSpeed: 10, context: context)
        XCTAssertEqual(model.title, "Intervals")
        XCTAssertEqual(model.structure, workout.structure)
        XCTAssertEqual(model.typicalEffort, 8)
    }

    func testFreeRunLinkedToAPlannedRunHasNoTargets() throws {
        let context = try makeContext()
        let monday = Calendar.kinetix.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 8))!
        PlanService.createPlan(for: SampleData.profile, in: context, now: monday)
        let planned = try XCTUnwrap(context.fetch(FetchDescriptor<PlannedSessionModel>()).first { $0.runStructure != nil })
        let model = RunWorkoutModel(planned: planned, custom: CustomRunWorkout.starter(for: .free, zones: nil), units: .metric,
                                    settings: nil, simulationSpeed: 10, context: context)
        XCTAssertNil(model.structure, "The runner's own (free) run replaces the planned structure")
        XCTAssertEqual(model.planned?.id, planned.id, "…but still ticks off the planned session")
    }

    func testTemplatesSync() throws {
        let context = try makeContext()
        let template = RunTemplateModel(workout: CustomRunWorkout.starter(for: .fartlek, zones: nil))
        context.insert(template)
        let record = try template.syncRecord()
        XCTAssertEqual(record.type, "runTemplate")
        let copy = RunTemplateModel.makeForSync(id: UUID())
        context.insert(copy)
        try copy.apply(record, context: context)
        XCTAssertEqual(copy.workout.blocks, template.workout.blocks)
    }
}

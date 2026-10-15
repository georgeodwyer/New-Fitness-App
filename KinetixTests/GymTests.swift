import XCTest
import SwiftData
import TrainingEngine
@testable import Kinetix

@MainActor
final class GymTests: XCTestCase {
    private var containers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try Persistence.makeContainer(inMemory: true)
        containers.append(container)
        return container.mainContext
    }

    private let bench = GymTemplateItem(exerciseId: "barbell-bench-press", name: "Barbell Bench Press", sets: 3, repsLow: 6, repsHigh: 8)
    private let pushUp = GymTemplateItem(exerciseId: "push-up", name: "Push-Up", sets: 2, repsLow: 10, repsHigh: 15, isBodyweight: true)

    func testFirstWorkoutUsesDefaultsThenNextOnePrefillsFromLastTime() throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        let first = GymService.start(title: "Push day", items: [bench, pushUp], linkedPlanned: nil, in: context, now: start)
        XCTAssertTrue(first.isRecorded)
        let firstBench = first.orderedSets.filter { $0.exerciseId == bench.exerciseId }
        XCTAssertEqual(firstBench.count, 3)
        XCTAssertEqual(firstBench.first?.targetReps, 8, "No history: top of the rep range")
        XCTAssertEqual(firstBench.first?.progressionKey, "barbell-bench-press.free", "Never moves plan weights")

        // Lift heavier than the default and finish.
        for (index, set) in firstBench.enumerated() {
            set.actualWeightKg = 62.5
            set.actualReps = 8 - index
            set.completedAt = start.addingTimeInterval(Double(index) * 120)
        }
        for set in first.orderedSets where set.exerciseId == pushUp.exerciseId {
            set.completedAt = start.addingTimeInterval(600)
        }
        let summary = StrengthService.finish(first, planned: nil, effort: 7, units: .metric, in: context, now: start.addingTimeInterval(2400))
        XCTAssertTrue(summary.changes.isEmpty, "Recorded workouts don't run plan progression")
        XCTAssertGreaterThan(first.load, 0, "…but count towards training load")
        XCTAssertTrue(try context.fetch(FetchDescriptor<ExerciseStateModel>()).isEmpty)

        let next = GymService.start(title: "Push day", items: [bench], linkedPlanned: nil, in: context, now: start.addingTimeInterval(86_400))
        let nextBench = next.orderedSets
        XCTAssertEqual(nextBench.map(\.actualWeightKg), [62.5, 62.5, 62.5])
        XCTAssertEqual(nextBench.map(\.actualReps), [8, 7, 6])
        XCTAssertEqual(GymService.lastTimeText(exerciseId: bench.exerciseId, isBodyweight: false, units: .metric, excluding: next, in: context),
                       "Last time: 62.5 kg × 8, 62.5 kg × 7, 62.5 kg × 6")
    }

    func testAddAndRemoveExercisesMidWorkout() throws {
        let context = try makeContext()
        let log = GymService.start(title: "", items: [], linkedPlanned: nil, in: context)
        XCTAssertEqual(log.title, "Gym workout")
        XCTAssertTrue(log.orderedSets.isEmpty)

        GymService.addExercise(bench, to: log, in: context)
        GymService.addExercise(pushUp, to: log, in: context)
        GymService.addExercise(bench, to: log, in: context) // already there: ignored
        XCTAssertEqual(log.orderedSets.count, 5)
        XCTAssertEqual(GymService.items(from: log).map(\.exerciseId), ["barbell-bench-press", "push-up"])
        XCTAssertEqual(GymService.items(from: log).map(\.sets), [3, 2])

        GymService.removeExercise(key: GymPrefill.freeKey(exerciseId: bench.exerciseId), from: log, in: context)
        XCTAssertEqual(GymService.items(from: log).map(\.exerciseId), ["push-up"])
        XCTAssertEqual(GymService.inProgress(in: context)?.id, log.id)
    }

    func testLinkedWorkoutTicksOffThePlannedSession() throws {
        let context = try makeContext()
        let monday = Calendar.kinetix.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 8))!
        PlanService.createPlan(for: SampleData.profile, in: context, now: monday)
        let planned = try XCTUnwrap(context.fetch(FetchDescriptor<PlannedSessionModel>()).first { $0.kind.discipline == .strength })
        let log = GymService.start(title: "My own", items: [bench], linkedPlanned: planned, in: context, now: planned.date)
        log.orderedSets.forEach { $0.completedAt = planned.date }
        _ = StrengthService.finish(log, planned: planned, effort: 6, units: .metric, in: context, now: planned.date.addingTimeInterval(1800))
        XCTAssertEqual(planned.status, .completed)
        XCTAssertEqual(log.plannedSessionId, planned.id)
    }

    func testCustomExercisesJoinTheLibrary() throws {
        let context = try makeContext()
        let custom = CustomExerciseModel(name: "Landmine Press", muscle: .shoulders, loading: .barbell)
        context.insert(custom)
        try context.save()
        let library = GymService.library(in: context)
        let found = try XCTUnwrap(library.first { $0.id == custom.exerciseId })
        XCTAssertEqual(found.muscleGroup, .shoulders)
        XCTAssertTrue(ExerciseSearch.filter(library, query: "landmine").contains { $0.id == custom.exerciseId })
    }

    func testGymTemplatesAndCustomExercisesSync() throws {
        let context = try makeContext()
        let template = GymTemplateModel(name: "Push day", items: [bench, pushUp])
        context.insert(template)
        let record = try template.syncRecord()
        XCTAssertEqual(record.type, "gymTemplate")
        let copy = GymTemplateModel.makeForSync(id: UUID())
        context.insert(copy)
        try copy.apply(record, context: context)
        XCTAssertEqual(copy.items, [bench, pushUp])
        XCTAssertEqual(copy.name, "Push day")

        let exercise = CustomExerciseModel(name: "Sled Push", muscle: .legs, loading: .machine)
        context.insert(exercise)
        let exerciseRecord = try exercise.syncRecord()
        XCTAssertEqual(exerciseRecord.type, "customExercise")
        let exerciseCopy = CustomExerciseModel.makeForSync(id: exercise.id)
        try exerciseCopy.apply(exerciseRecord, context: context)
        XCTAssertEqual(exerciseCopy.exerciseId, exercise.exerciseId)
        XCTAssertEqual(exerciseCopy.definition.loading, .machine)

        let log = StrengthLogModel(plannedSessionId: nil, startedAt: .now)
        log.isRecorded = true
        context.insert(log)
        let logCopy = StrengthLogModel.makeForSync(id: UUID())
        try logCopy.apply(log.syncRecord(), context: context)
        XCTAssertTrue(logCopy.isRecorded)
    }
}

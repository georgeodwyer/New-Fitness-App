import XCTest
@testable import TrainingEngine

final class PlanDayChangeTests: XCTestCase {
    func testKeptChangesShapeTheDayEveryWeek() throws {
        let templates = TestSupport.bundledTemplates
        let push = try XCTUnwrap(templates.programmes.strength?.split("ppl")?.days.first { $0.name == "Push" })
        var profile = TestSupport.profile(goal: .buildMuscle)
        let week = WeekTarget(index: 0, startDate: TestSupport.monday, phase: .build, weekInPhase: 0, isRecoveryWeek: false,
                              runVolumeMeters: 20000)
        let before = StrengthBuilder.prescription(for: push, context: .init(profile: profile, templates: templates, week: week,
                                                                             workingWeights: [:]))
        let first = try XCTUnwrap(before.exercises.first)
        let dropped = try XCTUnwrap(before.exercises.last)
        XCTAssertNotEqual(first.exerciseId, dropped.exerciseId)

        profile.planDayChanges = ["Push": PlanDayChange(
            added: [GymTemplateItem(exerciseId: "dumbbell-curl", name: "Dumbbell Curl", sets: 3, repsLow: 10, repsHigh: 12)],
            sets: [first.exerciseId: first.sets + 1],
            removed: [dropped.exerciseId])]
        let after = StrengthBuilder.prescription(for: push, context: .init(profile: profile, templates: templates, week: week,
                                                                            workingWeights: [:]))
        XCTAssertEqual(after.exercises.first { $0.exerciseId == first.exerciseId }?.sets, first.sets + 1)
        XCTAssertFalse(after.exercises.contains { $0.exerciseId == dropped.exerciseId })
        XCTAssertEqual(after.exercises.last?.exerciseId, "dumbbell-curl")
        XCTAssertEqual(after.exercises.last?.repRange, RepRange(10, 12))
    }
}

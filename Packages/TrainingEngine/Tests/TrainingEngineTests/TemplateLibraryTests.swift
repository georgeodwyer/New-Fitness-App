import XCTest
@testable import TrainingEngine

final class TemplateLibraryTests: XCTestCase {
    func testBundledTemplatesLoadAndValidate() throws {
        let library = try TemplateLibrary.bundled()
        XCTAssertFalse(library.runWorkouts.isEmpty)
        XCTAssertFalse(library.exercises.isEmpty)
        XCTAssertNoThrow(try library.validate())
    }

    func testExerciseChoiceFollowsEquipment() {
        let library = TestSupport.templates
        XCTAssertEqual(library.exercise(pattern: "horizontalPush", equipment: .fullGym)?.id, "barbell-bench-press")
        XCTAssertEqual(library.exercise(pattern: "horizontalPush", equipment: .dumbbellsOnly)?.id, "dumbbell-bench-press")
        XCTAssertEqual(library.exercise(pattern: "horizontalPush", equipment: .bodyweight)?.id, "push-up")
        XCTAssertEqual(library.exercise(pattern: "verticalPull", equipment: .fullGym)?.id, "lat-pulldown")
        XCTAssertEqual(library.exercise(pattern: "verticalPull", equipment: .homeGym)?.id, "pull-up")
    }

    func testSplitsBySessionCount() {
        let library = TestSupport.templates
        XCTAssertEqual(library.split(liftingDays: 2).map(\.focus), [.fullBody, .fullBody])
        XCTAssertEqual(library.split(liftingDays: 4).map(\.focus), [.upper, .lower, .upper, .lower])
        // More days than the largest split → largest split.
        XCTAssertEqual(library.split(liftingDays: 6).count, 4)
        XCTAssertTrue(library.split(liftingDays: 0).isEmpty)
    }

    func testValidationCatchesBrokenSplit() throws {
        var library = TestSupport.templates
        library.strength.splits["2"] = ["fullBodyA", "doesNotExist"]
        XCTAssertThrowsError(try library.validate())
    }
}

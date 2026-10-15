import XCTest
@testable import TrainingEngine

final class GymWorkoutTests: XCTestCase {
    private func kg(_ value: Double) -> String { "\(Units.formatWeight(kg: value, units: .metric)) kg" }

    func testPrefillCopiesLastTimeSetBySet() {
        let item = GymTemplateItem(exerciseId: "barbell-bench-press", name: "Bench", sets: 4, repsLow: 6, repsHigh: 8)
        let previous = [PreviousSet(weightKg: 60, reps: 8), PreviousSet(weightKg: 62.5, reps: 6), PreviousSet(weightKg: 62.5, reps: 5)]
        let sets = GymPrefill.sets(for: item, previous: previous, defaultWeightKg: 40)
        XCTAssertEqual(sets.map(\.weightKg), [60, 62.5, 62.5, 62.5])
        XCTAssertEqual(sets.map(\.reps), [8, 6, 5, 5])
    }

    func testPrefillWithoutHistoryUsesDefaultWeightAndTopOfRange() {
        let item = GymTemplateItem(exerciseId: "goblet-squat", name: "Goblet Squat", sets: 3, repsLow: 8, repsHigh: 12)
        let sets = GymPrefill.sets(for: item, previous: [], defaultWeightKg: 16)
        XCTAssertEqual(sets, Array(repeating: PrefilledSet(weightKg: 16, reps: 12), count: 3))
    }

    func testBodyweightPrefillHasNoWeight() {
        let item = GymTemplateItem(exerciseId: "push-up", name: "Push-Up", sets: 2, isBodyweight: true)
        let sets = GymPrefill.sets(for: item, previous: [PreviousSet(weightKg: 10, reps: 15)], defaultWeightKg: nil)
        XCTAssertEqual(sets.map(\.weightKg), [0, 0])
        XCTAssertEqual(sets.map(\.reps), [15, 15])
    }

    func testLastTimeText() {
        let same = Array(repeating: PreviousSet(weightKg: 60, reps: 8), count: 3)
        XCTAssertEqual(GymPrefill.lastTimeText(same, isBodyweight: false, formatWeight: kg), "Last time: 3 × 8 @ 60 kg")
        let mixed = [PreviousSet(weightKg: 60, reps: 8), PreviousSet(weightKg: 62.5, reps: 6)]
        XCTAssertEqual(GymPrefill.lastTimeText(mixed, isBodyweight: false, formatWeight: kg), "Last time: 60 kg × 8, 62.5 kg × 6")
        let bodyweight = [PreviousSet(weightKg: 0, reps: 12), PreviousSet(weightKg: 0, reps: 10)]
        XCTAssertEqual(GymPrefill.lastTimeText(bodyweight, isBodyweight: true, formatWeight: kg), "Last time: 12, 10 reps")
        XCTAssertNil(GymPrefill.lastTimeText([], isBodyweight: false, formatWeight: kg))
    }

    func testMuscleGroupsAndSearch() throws {
        let library = try TemplateLibrary.bundled()
        XCTAssertEqual(library.exercise(id: "barbell-bench-press")?.muscleGroup, .chest)
        XCTAssertEqual(library.exercise(id: "leg-curl")?.muscleGroup, .glutes)
        // Every muscle group has something to pick.
        for group in MuscleGroup.allCases {
            XCTAssertFalse(ExerciseSearch.filter(library.exercises, muscle: group).isEmpty, "\(group)")
        }
        let curls = ExerciseSearch.filter(library.exercises, query: "curl", loading: .dumbbell).map(\.name)
        XCTAssertTrue(curls.contains("Dumbbell Curl"))
        XCTAssertTrue(curls.contains("Hammer Curl"))
        XCTAssertFalse(curls.contains("Barbell Curl"))
        // Duplicate names in the plan library show once.
        XCTAssertEqual(ExerciseSearch.filter(library.exercises, query: "dumbbell romanian").count, 1)
    }

    func testLibraryOnlyExercisesAreNeverPickedForPlans() throws {
        let library = try TemplateLibrary.bundled()
        let patterns = Set(library.exercises.map(\.pattern))
        for pattern in patterns {
            for equipment in Equipment.allCases {
                XCTAssertNotEqual(library.exercise(pattern: pattern, equipment: equipment)?.libraryOnly, true)
            }
        }
        XCTAssertNil(library.exercise(pattern: "library", equipment: .fullGym))
        XCTAssertEqual(Set(library.exercises.map(\.id)).count, library.exercises.count, "Exercise ids must be unique")
    }

    func testTemplateSummaryAndStarter() throws {
        let library = try TemplateLibrary.bundled()
        let squat = GymTemplateItem.starter(for: try XCTUnwrap(library.exercise(id: "barbell-back-squat")))
        XCTAssertEqual(squat.setsAndReps, "3 × 5–8")
        XCTAssertEqual(squat.restSeconds, 150)
        let plank = GymTemplateItem.starter(for: try XCTUnwrap(library.exercise(id: "plank")))
        XCTAssertTrue(plank.isBodyweight)
        // 3 × (45 + 150) + 3 × (45 + 45) = 855 s ≈ 14 min, + 5 = 19.
        XCTAssertEqual(GymTemplate.summary([squat, plank]), "2 exercises · 6 sets · about 19 min")
    }
}

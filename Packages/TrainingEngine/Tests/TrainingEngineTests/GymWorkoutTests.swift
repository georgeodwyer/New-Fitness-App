import XCTest
@testable import TrainingEngine

final class GymWorkoutTests: XCTestCase {
    func testWeightFromLiftNumbers() {
        // 90 kg × 3 → 1RM 99 kg → 6 reps with 2 in reserve ≈ 78 kg → 77.5 kg on a barbell.
        let bench = LiftEstimate(lift: .benchPress, weightKg: 90, reps: 3)
        XCTAssertEqual(StrengthMath.weight(from: bench, reps: 6, accessory: false, loading: .barbell), 77.5)
        XCTAssertEqual(StrengthMath.weight(from: bench, reps: 6, accessory: true, loading: .barbell), 62.5)
    }

    func testAlternativesPreferTheSameMovementAndRespectEquipment() throws {
        let library = TestSupport.bundledTemplates
        let bench = library.alternatives(to: "barbell-bench-press", equipment: .fullGym)
        XCTAssertFalse(bench.isEmpty)
        XCTAssertEqual(bench.first?.pattern, "horizontalPush", "Another horizontal press comes first")
        XCTAssertFalse(bench.contains { $0.id == "barbell-bench-press" })
        let dumbbellsOnly = library.alternatives(to: "barbell-bench-press", equipment: .dumbbellsOnly)
        XCTAssertTrue(dumbbellsOnly.allSatisfy { Equipment.dumbbellsOnly.allows($0.requires) })
        XCTAssertTrue(library.alternatives(to: "not-an-exercise", equipment: .fullGym).isEmpty)
    }

    func testKeptSwapIsUsedInFuturePlans() throws {
        var profile = TestSupport.profile(goal: .buildStrength, days: [.monday, .wednesday, .friday, .saturday])
        let generator = PlanGenerator(templates: TestSupport.bundledTemplates)
        let outline = generator.makeOutline(for: profile, startingOn: TestSupport.monday)
        let week = try XCTUnwrap(generator.generateWeek(0, outline: outline, profile: profile))
        let session = try XCTUnwrap(week.sessions.first { $0.strength?.exercises.contains { $0.exerciseId == "barbell-back-squat" } == true })
        profile.exerciseSwaps = [AthleteProfile.swapKey(day: session.title, exerciseId: "barbell-back-squat"): "leg-press"]
        let swapped = try XCTUnwrap(generator.generateWeek(0, outline: outline, profile: profile))
        let same = try XCTUnwrap(swapped.sessions.first { $0.title == session.title && $0.date == session.date })
        XCTAssertTrue(same.strength?.exercises.contains { $0.exerciseId == "leg-press" } ?? false)
        XCTAssertFalse(same.strength?.exercises.contains { $0.exerciseId == "barbell-back-squat" } ?? true)
    }

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

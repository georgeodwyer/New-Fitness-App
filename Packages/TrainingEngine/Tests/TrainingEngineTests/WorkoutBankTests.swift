import XCTest
@testable import TrainingEngine

final class WorkoutBankTests: XCTestCase {
    func testBankHasEverySplitsSessionsForTheEquipment() throws {
        let bank = TestSupport.bundledTemplates.workoutBank(equipment: .fullGym, goal: .balancedHybrid)
        let ppl = try XCTUnwrap(bank.first { $0.id == "ppl" })
        XCTAssertEqual(ppl.workouts.map(\.name), ["Push", "Pull", "Legs"])
        XCTAssertTrue(ppl.workouts.allSatisfy { !$0.items.isEmpty })
        XCTAssertTrue(ppl.workouts.allSatisfy { Set($0.items.map(\.exerciseId)).count == $0.items.count }, "No exercise twice")
        // Dumbbells only: nothing that needs a barbell or a machine.
        let home = TestSupport.bundledTemplates.workoutBank(equipment: .dumbbellsOnly, goal: .balancedHybrid)
        let library = TestSupport.bundledTemplates.exercises
        for workout in home.flatMap(\.workouts) {
            for item in workout.items {
                let exercise = try XCTUnwrap(library.first { $0.id == item.exerciseId })
                XCTAssertTrue(Equipment.dumbbellsOnly.allows(exercise.requires), "\(item.name) in \(workout.name)")
            }
        }
    }
}

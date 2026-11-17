import XCTest
@testable import TrainingEngine

final class FocusSplitTests: XCTestCase {
    private let library = TestSupport.bundledTemplates
    private let focusCodes = ["glutes2", "glutes3", "glutes4", "upperArms2", "upperArms3", "upperArms4"]

    /// Every slot of every focus split gives a different exercise for each kind of equipment,
    /// and every week has arm work (George: arms get missed).
    func testFocusSplitsWorkForAllEquipmentAndIncludeArms() throws {
        for equipment in Equipment.allCases {
            let groups = library.workoutBank(equipment: equipment, goal: .balancedHybrid)
            for code in focusCodes {
                let split = try XCTUnwrap(library.programmes.strength?.split(code), code)
                let group = try XCTUnwrap(groups.first { $0.id == code }, code)
                // Bodyweight only: a dumbbell exercise with no bodyweight version drops out.
                for (day, workout) in zip(split.days, group.workouts) where equipment != .bodyweight {
                    XCTAssertEqual(workout.items.count, day.slots.count,
                                   "\(code) \(day.name) with \(equipment.rawValue): \(workout.items.map(\.name))")
                }
                let muscles = group.workouts.flatMap(\.items).compactMap { library.exercise(id: $0.exerciseId)?.muscleGroup }
                XCTAssertTrue(muscles.contains(.arms), "\(code) with \(equipment.rawValue) has no arms")
            }
        }
    }

    func testGluteWorkSuitsTheEquipment() throws {
        func names(_ equipment: Equipment) -> [String] {
            library.workoutBank(equipment: equipment, goal: .balancedHybrid).first { $0.id == "glutes3" }?.workouts.flatMap(\.items).map(\.name) ?? []
        }
        XCTAssertTrue(names(.fullGym).contains("Barbell Hip Thrust"))
        XCTAssertTrue(names(.fullGym).contains("Hip Abduction Machine"))
        XCTAssertTrue(names(.dumbbellsOnly).contains("Dumbbell Hip Thrust"))
        XCTAssertTrue(names(.bodyweight).contains("Glute Bridge"))
        XCTAssertTrue(names(.bodyweight).contains("Banded Hip Abduction"))
    }

    func testAPlanUsesTheChosenFocusSplit() {
        var profile = TestSupport.profile(running: .intermediate, goal: .faster10k)
        profile.splitCode = "glutes3"
        let days = library.liftTemplates(for: profile, count: 3).map(\.name)
        XCTAssertEqual(days, ["Lower A", "Upper", "Lower B"])
    }
}

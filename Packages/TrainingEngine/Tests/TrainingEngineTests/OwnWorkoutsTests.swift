import XCTest
@testable import TrainingEngine

final class OwnWorkoutsTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private var generator: PlanGenerator { PlanGenerator(templates: TestSupport.bundledTemplates, calendar: calendar) }

    private func profile(_ style: PlanStyle) -> AthleteProfile {
        var profile = TestSupport.profile(goal: .halfMarathon, days: [.monday, .tuesday, .thursday, .saturday, .sunday], doubles: 1)
        profile.weeklyRunMeters = 30_000
        profile.longestRecentRunMeters = 12_000
        profile.liftSessionsPerWeek = 2
        profile.planStyle = style
        return profile
    }

    private func week(_ profile: AthleteProfile, _ index: Int = 1) -> GeneratedWeek {
        let outline = generator.makeOutline(for: profile, startingOn: TestSupport.monday)
        return generator.generateWeek(index, outline: outline, profile: profile)!
    }

    func testOwnGymDaysArePlaceholdersUntilLinked() {
        let lifts = week(profile(.ownGym)).sessions.filter { $0.kind.discipline == .strength }
        XCTAssertEqual(lifts.map(\.title), ["Gym 1", "Gym 2"])
        XCTAssertTrue(lifts.allSatisfy { $0.strength == nil })
    }

    func testLinkedGymWorkoutsFillTheDays() {
        var athlete = profile(.ownGym)
        let legs = OwnGymWorkout(name: "Legs", exercises: [
            GymTemplateItem(exerciseId: "barbell-back-squat", name: "Barbell Back Squat", sets: 4, repsLow: 5, repsHigh: 8),
            GymTemplateItem(exerciseId: "barbell-rdl", name: "Romanian Deadlift", sets: 3)
        ])
        let push = OwnGymWorkout(name: "Push", exercises: [
            GymTemplateItem(exerciseId: "barbell-bench-press", name: "Barbell Bench Press", sets: 4)
        ])
        athlete.ownGymWorkouts = [1: legs, 2: push]
        let lifts = week(athlete).sessions.filter { $0.kind.discipline == .strength }
        let legDay = lifts.first { $0.title == "Gym 1 · Legs" }
        XCTAssertNotNil(legDay)
        XCTAssertEqual(legDay?.kind, .strength(.legs))
        XCTAssertEqual(legDay?.strength?.exercises.count, 2)
        XCTAssertEqual(lifts.first { $0.title == "Gym 2 · Push" }?.kind, .strength(.push))
    }

    func testOwnRunsHaveRolesAndLinkedWorkouts() {
        var athlete = profile(.ownRuns)
        let tempo = CustomRunWorkout(name: "My tempo", type: .tempo, blocks: [
            RunBlock(repeats: 1, steps: [WorkoutStep(kind: .work, length: .duration(seconds: 1200))])
        ])
        athlete.ownRunWorkouts = [.quality1: tempo]
        let runs = week(athlete).sessions.filter { $0.kind.discipline == .run }
        XCTAssertTrue(runs.contains { $0.title.hasPrefix("Run") && $0.title.contains("Long") })
        XCTAssertTrue(runs.contains { $0.title.contains("Quality: My tempo") })
        XCTAssertEqual(runs.first.map { $0.title.hasPrefix("Run 1 ·") }, true)
        // Gym is still Kinetix's.
        XCTAssertTrue(week(athlete).sessions.filter { $0.kind.discipline == .strength }.allSatisfy { $0.strength != nil })
    }

    func testFocusFromExercises() {
        let library = TestSupport.bundledTemplates.exercises
        XCTAssertEqual(OwnWorkouts.focus(of: [GymTemplateItem(exerciseId: "x", name: "Lat Pulldown")], library: library), .pull)
        XCTAssertEqual(OwnWorkouts.focus(of: [GymTemplateItem(exerciseId: "barbell-back-squat", name: "Barbell Back Squat")], library: library), .legs)
    }
}

import XCTest
@testable import TrainingEngine

final class ProgressionTests: XCTestCase {
    private let range = RepRange(6, 8)

    private func evaluate(
        loading: ExerciseLoading = .barbell,
        region: BodyRegion = .lower,
        state: ProgressionState = ProgressionState(workingWeightKg: 100),
        sets: [SetResult]
    ) -> ProgressionDecision {
        Progression.evaluate(exerciseName: "Squat", loading: loading, region: region, repRange: range,
                             prescribedSets: 3, state: state, sets: sets)
    }

    private func sets(_ reps: [Int], weight: Double = 100, rpe: Double? = nil) -> [SetResult] {
        reps.map { SetResult(weightKg: weight, reps: $0, rpe: rpe) }
    }

    func testIncreaseWhenAllSetsHitTopOfRange() {
        let decision = evaluate(sets: sets([8, 8, 8], rpe: 8))
        XCTAssertEqual(decision.change, .increase(byKg: 5))
        XCTAssertEqual(decision.newState, ProgressionState(workingWeightKg: 105, stallCount: 0))
        XCTAssertTrue(decision.reason.contains("+5 kg to 105 kg"))
        XCTAssertTrue(decision.reason.contains("RPE 8"))
    }

    func testUpperBodyUsesSmallerIncrement() {
        let decision = evaluate(region: .upper, state: ProgressionState(workingWeightKg: 60), sets: sets([8, 8, 8], weight: 60))
        XCTAssertEqual(decision.change, .increase(byKg: 2.5))
        XCTAssertEqual(decision.newState.workingWeightKg, 62.5)
    }

    func testVeryHardEffortHoldsInsteadOfIncreasing() {
        let decision = evaluate(sets: sets([8, 8, 8], rpe: 10))
        XCTAssertEqual(decision.change, .hold)
        XCTAssertEqual(decision.newState.workingWeightKg, 100)
    }

    func testInRangeHoldsWithoutCountingAsStall() {
        let decision = evaluate(state: ProgressionState(workingWeightKg: 100, stallCount: 2), sets: sets([8, 7, 6]))
        XCTAssertEqual(decision.change, .hold)
        XCTAssertEqual(decision.newState.stallCount, 0)
        XCTAssertTrue(decision.reason.contains("Aim for 8 reps"))
    }

    func testMissedRepsHoldAndCountStall() {
        let decision = evaluate(sets: sets([7, 6, 4]))
        XCTAssertEqual(decision.change, .hold)
        XCTAssertEqual(decision.newState, ProgressionState(workingWeightKg: 100, stallCount: 1))
    }

    func testMissingASetCountsAsMissedReps() {
        let decision = evaluate(sets: sets([8, 8]))
        XCTAssertEqual(decision.newState.stallCount, 1)
    }

    func testRepeatedStallsTriggerDeload() {
        let decision = evaluate(state: ProgressionState(workingWeightKg: 100, stallCount: 2), sets: sets([6, 5, 4]))
        XCTAssertEqual(decision.change, .deload(byKg: 10))
        XCTAssertEqual(decision.newState, ProgressionState(workingWeightKg: 90, stallCount: 0))
        XCTAssertTrue(decision.reason.contains("3 sessions running"))
    }

    func testProgressionUsesWeightActuallyLifted() {
        // Prescribed 100 kg but the user chose 95 kg and hit every rep: next is 100 kg.
        let decision = evaluate(sets: sets([8, 8, 8], weight: 95))
        XCTAssertEqual(decision.newState.workingWeightKg, 100)
    }

    func testNothingLoggedChangesNothing() {
        let state = ProgressionState(workingWeightKg: 100, stallCount: 1)
        let decision = evaluate(state: state, sets: [SetResult(weightKg: 100, reps: 8, completed: false)])
        XCTAssertEqual(decision.change, .none)
        XCTAssertEqual(decision.newState, state)
    }

    func testBodyweightExercisesNeverChangeWeight() {
        let decision = evaluate(loading: .bodyweight, sets: [SetResult(weightKg: nil, reps: 8), SetResult(weightKg: nil, reps: 8), SetResult(weightKg: nil, reps: 8)])
        XCTAssertEqual(decision.change, .none)
        XCTAssertTrue(decision.reason.contains("harder"))
    }

    func testImperialReasonText() {
        let decision = Progression.evaluate(exerciseName: "Bench", loading: .barbell, region: .upper, repRange: range,
                                            prescribedSets: 3, state: ProgressionState(workingWeightKg: 60),
                                            sets: sets([8, 8, 8], weight: 60), units: .imperial)
        XCTAssertTrue(decision.reason.contains("lb"))
    }

    func testRulesLoadFromTemplates() {
        let rules = TestSupport.templates.strength.progressionRules
        XCTAssertEqual(rules.increment(loading: .barbell, region: .lower), 5)
        XCTAssertEqual(rules.increment(loading: .barbell, region: .upper), 2.5)
        XCTAssertEqual(rules.stallsBeforeDeload, 3)
    }
}

final class RecordsAndLoadTests: XCTestCase {
    func testBestsAndNewRecords() {
        let sets = [SetResult(weightKg: 100, reps: 5), SetResult(weightKg: 105, reps: 3), SetResult(weightKg: 100, reps: 5, completed: false)]
        let bests = PersonalRecords.bests(in: sets)
        XCTAssertEqual(bests[.heaviestWeight], 105)
        XCTAssertEqual(bests[.estimatedOneRepMax] ?? 0, 116.67, accuracy: 0.01) // 100 × (1 + 5/30)
        XCTAssertEqual(bests[.sessionVolume], 815)

        let records = PersonalRecords.newRecords(sets: sets, previousBests: [.heaviestWeight: 102.5, .estimatedOneRepMax: 120, .sessionVolume: 700])
        XCTAssertEqual(records.map(\.kind), [.heaviestWeight, .sessionVolume])
        XCTAssertEqual(records.first?.previous, 102.5)
    }

    func testFirstSessionSetsNoRecords() {
        XCTAssertTrue(PersonalRecords.newRecords(sets: [SetResult(weightKg: 50, reps: 5)], previousBests: [:]).isEmpty)
    }

    func testSessionLoadAndVolume() {
        XCTAssertEqual(SessionLoad.srpe(durationSeconds: 3600, effort: 7), 420)
        XCTAssertEqual(SessionLoad.volumeKg([SetResult(weightKg: 50, reps: 10), SetResult(weightKg: nil, reps: 10)]), 500)
    }
}

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

    func testFinishingEarlyHoldsWithoutCountingAsStall() {
        // Two of three sets, both good: a session cut short, not a failure.
        let decision = evaluate(state: ProgressionState(workingWeightKg: 100, stallCount: 1), sets: sets([8, 8]))
        XCTAssertEqual(decision.change, .hold)
        XCTAssertEqual(decision.newState, ProgressionState(workingWeightKg: 100, stallCount: 1))
        XCTAssertTrue(decision.reason.contains("2 of 3 sets"))
    }

    func testRepeatedStallsTriggerDeload() {
        let decision = evaluate(state: ProgressionState(workingWeightKg: 100, stallCount: 2), sets: sets([6, 5, 4]))
        XCTAssertEqual(decision.change, .deload(byKg: 10))
        XCTAssertEqual(decision.newState, ProgressionState(workingWeightKg: 90, stallCount: 0))
        XCTAssertTrue(decision.reason.contains("3 sessions running"))
    }

    func testProgressionUsesWeightActuallyLifted() {
        // Prescribed 100 kg but the user chose 95 kg and hit every rep: next is 97.5 kg (under
        // 100 kg, lower-body lifts go up 2.5 kg).
        let decision = evaluate(sets: sets([8, 8, 8], weight: 95))
        XCTAssertEqual(decision.newState.workingWeightKg, 97.5)
    }

    func testLowerBodyStepScalesWithTheWeight() {
        let light = evaluate(state: ProgressionState(workingWeightKg: 70), sets: sets([8, 8, 8], weight: 70))
        XCTAssertEqual(light.change, .increase(byKg: 2.5))
        let heavy = evaluate(state: ProgressionState(workingWeightKg: 120), sets: sets([8, 8, 8], weight: 120))
        XCTAssertEqual(heavy.change, .increase(byKg: 5))
    }

    func testLightDumbbellsEarnTheirStepWithExtraReps() {
        // 2 kg on 8 kg is a 25% jump: 12s at the top of an 8–12 range hold; 14s earn it.
        func raise(_ reps: Int) -> ProgressionDecision {
            Progression.evaluate(exerciseName: "Lateral raise", loading: .dumbbell, region: .upper, repRange: RepRange(8, 12),
                                 prescribedSets: 2, state: ProgressionState(workingWeightKg: 8),
                                 sets: [reps, reps].map { SetResult(weightKg: 8, reps: $0) })
        }
        XCTAssertEqual(raise(12).change, .hold)
        XCTAssertTrue(raise(12).reason.contains("aim for 14 reps"))
        XCTAssertEqual(raise(14).change, .increase(byKg: 2))
        // 2 kg on 24 kg is a normal step: the top of the range is enough.
        let row = Progression.evaluate(exerciseName: "Row", loading: .dumbbell, region: .upper, repRange: RepRange(8, 12),
                                       prescribedSets: 2, state: ProgressionState(workingWeightKg: 24),
                                       sets: [12, 12].map { SetResult(weightKg: 24, reps: $0) })
        XCTAssertEqual(row.change, .increase(byKg: 2))
    }

    func testLightLiftsAreNeverResetForFallingShortAfterABigStep() {
        // 10 kg lateral raises after going up from 8 kg: 6 reps is short of 8, but expected.
        let decision = Progression.evaluate(exerciseName: "Lateral raise", loading: .dumbbell, region: .upper, repRange: RepRange(8, 12),
                                            prescribedSets: 2, state: ProgressionState(workingWeightKg: 10, stallCount: 2),
                                            sets: [6, 6].map { SetResult(weightKg: 10, reps: $0) })
        XCTAssertEqual(decision.change, .hold)
        XCTAssertEqual(decision.newState, ProgressionState(workingWeightKg: 10, stallCount: 0))
    }

    func testMissesOnALowRecoveryDayDontCountTowardsAReset() {
        let decision = Progression.evaluate(exerciseName: "Squat", loading: .barbell, region: .lower, repRange: range,
                                            prescribedSets: 3, state: ProgressionState(workingWeightKg: 100, stallCount: 2),
                                            sets: sets([6, 5, 4]), countsMisses: false)
        XCTAssertEqual(decision.change, .hold)
        XCTAssertEqual(decision.newState, ProgressionState(workingWeightKg: 100, stallCount: 2))
        XCTAssertTrue(decision.reason.contains("recovery was low"))
    }

    func testHeavyWeekWeight() {
        XCTAssertEqual(StrengthMath.heavyWeight(working: 70, loading: .barbell), 72.5)
        XCTAssertEqual(StrengthMath.heavyWeight(working: 100, loading: .barbell), 105)
        XCTAssertEqual(StrengthMath.heavyWeight(working: 20, loading: .dumbbell), 22)
    }

    func testWeightStaysUntilEverySetReachesTheTarget() {
        // Programmed 3 × 8 @ 80 (range 6–8): 8, 8, 6 holds at 80 kg.
        let bench = Progression.evaluate(exerciseName: "Bench", loading: .barbell, region: .upper, repRange: RepRange(6, 8),
                                         prescribedSets: 3, state: ProgressionState(workingWeightKg: 80),
                                         sets: [8, 8, 6].map { SetResult(weightKg: 80, reps: $0) })
        XCTAssertEqual(bench.change, .hold)
        XCTAssertEqual(bench.newState.workingWeightKg, 80)
        // All three at 8: up.
        let next = Progression.evaluate(exerciseName: "Bench", loading: .barbell, region: .upper, repRange: RepRange(6, 8),
                                        prescribedSets: 3, state: ProgressionState(workingWeightKg: 80),
                                        sets: [8, 8, 8].map { SetResult(weightKg: 80, reps: $0) })
        XCTAssertEqual(next.newState.workingWeightKg, 82.5)
    }

    func testOneLighterSetHoldsTheWorkingWeight() {
        // Two sets at 100, the last dropped to 90: no increase, and the weight stays 100 (not 90).
        let decision = evaluate(sets: [SetResult(weightKg: 100, reps: 8), SetResult(weightKg: 100, reps: 8),
                                       SetResult(weightKg: 90, reps: 8)])
        XCTAssertEqual(decision.change, .hold)
        XCTAssertEqual(decision.newState.workingWeightKg, 100)
        XCTAssertTrue(decision.reason.contains("2 of 3 sets at that weight"))
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

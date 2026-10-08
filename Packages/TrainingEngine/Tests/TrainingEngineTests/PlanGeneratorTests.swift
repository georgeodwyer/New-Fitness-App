import XCTest
@testable import TrainingEngine

final class PlanGeneratorTests: XCTestCase {
    private let generator = TestSupport.generator
    private let calendar = TestSupport.calendar

    private func fullPlan(_ profile: AthleteProfile) -> [GeneratedWeek] {
        let outline = generator.makeOutline(for: profile, startingOn: TestSupport.monday)
        return outline.weeks.indices.compactMap { generator.generateWeek($0, outline: outline, profile: profile) }
    }

    func testPlanStartDate() {
        XCTAssertEqual(generator.planStart(from: TestSupport.date(2026, 10, 7)), TestSupport.monday) // Wednesday
        XCTAssertEqual(generator.planStart(from: TestSupport.date(2026, 10, 8)), TestSupport.date(2026, 10, 12)) // Thursday
    }

    func testEveryWeekIsWellFormed() {
        let event = calendar.date(byAdding: .day, value: 13 * 7 + 6, to: TestSupport.monday)!
        let profile = TestSupport.profile(goal: .halfMarathon, event: event)
        let weeks = fullPlan(profile)
        XCTAssertEqual(weeks.count, 14)
        for week in weeks {
            let weekdays = Set(week.sessions.map { calendar.weekday(of: $0.date) })
            XCTAssertTrue(weekdays.isSubset(of: Set(profile.trainingDays)))
            XCTAssertLessThan(weekdays.count, 7, "Needs a rest day")
            for session in week.sessions {
                XCTAssertGreaterThanOrEqual(session.date, week.target.startDate)
                XCTAssertGreaterThan(session.plannedDurationMinutes, 0)
                switch session.kind {
                case .run:
                    let structure = try! XCTUnwrap(session.runStructure)
                    XCTAssertFalse(structure.segments.isEmpty)
                    XCTAssertTrue(structure.segments.allSatisfy { $0.targetPace != nil })
                case .strength:
                    let strength = try! XCTUnwrap(session.strength)
                    XCTAssertGreaterThanOrEqual(strength.exercises.count, 3)
                    for exercise in strength.exercises {
                        let isBodyweight = TestSupport.templates.exercise(id: exercise.exerciseId)?.loading == .bodyweight
                        XCTAssertEqual(exercise.weightKg == nil, isBodyweight, exercise.exerciseId)
                    }
                case .crossTraining:
                    XCTAssertNil(session.runStructure)
                case .mobility:
                    XCTFail("Plans don't generate mobility sessions yet")
                }
            }
        }
    }

    func testPlannedRunningVolumeTracksTarget() {
        let profile = TestSupport.profile(goal: .halfMarathon, days: [.monday, .tuesday, .wednesday, .thursday, .saturday, .sunday], doubles: 1)
        for week in fullPlan(profile) {
            let ratio = week.plannedRunMeters / week.target.runVolumeMeters
            // Taper weeks keep minimum run lengths, so they can sit a little above target.
            let tolerance = week.target.phase == .taper ? 0.35 : 0.25
            XCTAssertEqual(ratio, 1, accuracy: tolerance, "Week \(week.target.index): planned \(week.plannedRunMeters) vs target \(week.target.runVolumeMeters)")
        }
    }

    func testQualityWorkoutsProgressThroughBuildPhase() {
        let profile = TestSupport.profile(goal: .faster10k)
        let outline = generator.makeOutline(for: profile, startingOn: TestSupport.monday)
        let buildWeeks = outline.weeks.filter { $0.phase == .build && !$0.isRecoveryWeek }
        XCTAssertGreaterThanOrEqual(buildWeeks.count, 2)
        let first = generator.generateWeek(buildWeeks[0].index, outline: outline, profile: profile)!
        let second = generator.generateWeek(buildWeeks[1].index, outline: outline, profile: profile)!
        let firstIntervals = first.sessions.first { $0.kind == .run(.intervals) }?.summary
        let secondIntervals = second.sessions.first { $0.kind == .run(.intervals) }?.summary
        XCTAssertNotNil(firstIntervals)
        XCTAssertNotEqual(firstIntervals, secondIntervals)
    }

    func testStartingWeightFromEstimate() {
        // 100 kg × 5 → e1RM ≈ 116.7 kg. Strength goal works at 4-6 reps with ~2 in reserve
        // → 116.7 / (1 + 6/30) ≈ 97.2 → rounded down to 95 kg.
        let profile = TestSupport.profile(goal: .buildStrength, days: [.monday, .wednesday, .friday, .saturday],
                                          estimates: [LiftEstimate(lift: .squat, weightKg: 100, reps: 5)])
        let outline = generator.makeOutline(for: profile, startingOn: TestSupport.monday)
        let week = generator.generateWeek(0, outline: outline, profile: profile)!
        let squat = week.sessions.compactMap(\.strength).flatMap(\.exercises).first { $0.exerciseId == "barbell-back-squat" && $0.role == .main }
        XCTAssertEqual(squat?.weightKg, 95)
        XCTAssertEqual(squat?.repRange, RepRange(4, 6))
    }

    func testWorkingWeightsOverrideStartingWeights() {
        let profile = TestSupport.profile(goal: .buildStrength, days: [.monday, .wednesday, .friday, .saturday])
        let outline = generator.makeOutline(for: profile, startingOn: TestSupport.monday)
        let week = generator.generateWeek(0, outline: outline, profile: profile,
                                          workingWeights: ["barbell-back-squat.main": 123.5])!
        let squat = week.sessions.compactMap(\.strength).flatMap(\.exercises).first { $0.progressionKey == "barbell-back-squat.main" }
        XCTAssertEqual(squat?.weightKg, 123.5)
    }

    func testBodyweightEquipmentHasNoLoads() {
        let profile = TestSupport.profile(goal: .balancedHybrid, equipment: .bodyweight)
        let outline = generator.makeOutline(for: profile, startingOn: TestSupport.monday)
        let week = generator.generateWeek(0, outline: outline, profile: profile)!
        let exercises = week.sessions.compactMap(\.strength).flatMap(\.exercises)
        XCTAssertFalse(exercises.isEmpty)
        XCTAssertTrue(exercises.allSatisfy { $0.weightKg == nil })
    }

    func testNotBeforeOmitsPastDays() {
        let profile = TestSupport.profile()
        let outline = generator.makeOutline(for: profile, startingOn: TestSupport.monday)
        let thursday = TestSupport.date(2026, 10, 8)
        let week = generator.generateWeek(0, outline: outline, profile: profile, notBefore: thursday)!
        XCTAssertTrue(week.sessions.allSatisfy { $0.date >= thursday })
    }

    func testGenerationIsDeterministic() {
        let profile = TestSupport.profile()
        let outline = generator.makeOutline(for: profile, startingOn: TestSupport.monday)
        XCTAssertEqual(generator.generateWeek(2, outline: outline, profile: profile),
                       generator.generateWeek(2, outline: outline, profile: profile))
    }

    func testStrengthGoalKeepsAllLifts() {
        // Lifts get first pick of days for strength goals; runs fit around them.
        let profile = TestSupport.profile(goal: .buildStrength, days: [.monday, .wednesday, .friday, .saturday])
        let outline = generator.makeOutline(for: profile, startingOn: TestSupport.monday)
        let week = generator.generateWeek(4, outline: outline, profile: profile)!
        let expectedLifts = generator.weeklyMixCounts(for: profile).lifts
        XCTAssertEqual(week.sessions.filter { $0.kind.discipline == .strength }.count, expectedLifts)
    }

    func testOverfullWeekSwapsEasyRunsForCrossTraining() {
        // Two quality sessions plus a long run fill a modest week, so easy runs become cardio.
        let profile = TestSupport.profile(goal: .halfMarathon, days: [.monday, .tuesday, .wednesday, .thursday, .saturday, .sunday], doubles: 1)
        let outline = generator.makeOutline(for: profile, startingOn: TestSupport.monday)
        let week = generator.generateWeek(4, outline: outline, profile: profile)!
        XCTAssertTrue(week.sessions.contains { $0.kind == .crossTraining })
        XCTAssertTrue(week.notes.contains { $0.contains("low-impact") })
    }

    func testKeySessionsFollowGoal() {
        let runner = fullPlan(TestSupport.profile(goal: .halfMarathon))[4]
        XCTAssertTrue(runner.sessions.filter(\.isKey).allSatisfy { $0.kind.discipline == .run })
        let lifter = fullPlan(TestSupport.profile(goal: .buildMuscle))[4]
        XCTAssertTrue(lifter.sessions.filter(\.isKey).allSatisfy { $0.kind.discipline == .strength })
    }
}

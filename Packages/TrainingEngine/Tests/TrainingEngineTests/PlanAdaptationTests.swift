import XCTest
@testable import TrainingEngine

/// Lighter weeks, growth that follows how the weeks went, heavy gym weeks and topped-up weeks.
final class PlanAdaptationTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private var generator: PlanGenerator { PlanGenerator(templates: TestSupport.bundledTemplates, calendar: calendar) }
    private let start = TestSupport.date(2026, 10, 26)

    private var profile: AthleteProfile {
        AthleteProfile(runningExperience: .intermediate, recentRace: RaceResult(distanceMeters: 5000, timeSeconds: 22 * 60),
                       liftingExperience: .intermediate, goal: .faster10k,
                       trainingDays: [.monday, .tuesday, .wednesday, .thursday, .saturday, .sunday], doubleSessionDays: 3,
                       equipment: .fullGym, weeklyRunMeters: 16500, longestRecentRunMeters: 6000,
                       liftSessionsPerWeek: 5, splitCode: "pplUpperArms", longRunDay: .sunday)
    }

    func testLighterWeeksAreAtLeast15PercentLighter() {
        let outline = generator.makeOutline(for: profile, startingOn: start)
        for (i, week) in outline.weeks.enumerated() where week.isRecoveryWeek && week.programmeWeek != nil && i > 0 {
            XCTAssertLessThanOrEqual(week.runVolumeMeters, outline.weeks[i - 1].runVolumeMeters * 0.85 + 1, "Week \(i + 1)")
        }
        // Weeks keep their base, so the rest of the plan can be resized.
        XCTAssertNotNil(outline.weeks[2].base)
    }

    func testDecisions() {
        typealias R = PlanAdaptation.WeekResult
        XCTAssertTrue(PlanAdaptation.decide([R(plannedRunMeters: 20000, doneRunMeters: 14000, feel: nil),
                                             R(plannedRunMeters: 22000, doneRunMeters: 15000, feel: nil)]).hold)
        // One short week isn't enough.
        XCTAssertFalse(PlanAdaptation.decide([R(plannedRunMeters: 20000, doneRunMeters: 20000, feel: nil),
                                              R(plannedRunMeters: 22000, doneRunMeters: 10000, feel: nil)]).changesPlan)
        XCTAssertTrue(PlanAdaptation.decide([R(plannedRunMeters: 20000, doneRunMeters: 20000, feel: .tooMuch),
                                             R(plannedRunMeters: 22000, doneRunMeters: 22000, feel: .tooMuch)]).hold)
        let easy = PlanAdaptation.decide([R(plannedRunMeters: 20000, doneRunMeters: 20000, feel: .tooEasy),
                                          R(plannedRunMeters: 22000, doneRunMeters: 22000, feel: .tooEasy)])
        XCTAssertFalse(easy.hold)
        XCTAssertEqual(easy.limit, 0.15)
        // Missed runs win over "too easy".
        XCTAssertTrue(PlanAdaptation.decide([R(plannedRunMeters: 20000, doneRunMeters: 10000, feel: .tooEasy),
                                             R(plannedRunMeters: 22000, doneRunMeters: 10000, feel: .tooEasy)]).hold)
    }

    func testHoldingPausesGrowthForAWeekThenGrowsAgain() throws {
        let outline = generator.makeOutline(for: profile, startingOn: start)
        let decision = PlanAdaptation.Decision(hold: true, limit: nil, reason: nil)
        let held = try XCTUnwrap(generator.adaptedOutline(outline, from: 5, decision: decision, profile: profile))
        // Weeks before stay as they were.
        XCTAssertEqual(held.weeks.prefix(5).map(\.runVolumeMeters), outline.weeks.prefix(5).map(\.runVolumeMeters))
        // Week 6 doesn't grow: same base, no more running than week 5.
        XCTAssertEqual(held.weeks[5].base ?? 0, held.weeks[4].base ?? -1, accuracy: 0.5)
        XCTAssertLessThanOrEqual(held.weeks[5].runVolumeMeters, held.weeks[4].runVolumeMeters + 1)
        XCTAssertLessThan(held.weeks[5].runVolumeMeters, outline.weeks[5].runVolumeMeters)
        // Then it grows again (week 7 is a normal week).
        XCTAssertGreaterThan(held.weeks[6].base ?? 0, held.weeks[5].base ?? 0)
        // Every week still within 10% of the three before.
        for i in 1..<held.weeks.count {
            let recent = held.weeks[max(0, i - 3)..<i].map(\.runVolumeMeters).max() ?? 0
            XCTAssertLessThanOrEqual(held.weeks[i].runVolumeMeters, recent * 1.1 + 1, "Week \(i + 1)")
        }
    }

    func testTooEasyAllowsUpTo15PercentForOneWeek() throws {
        let outline = generator.makeOutline(for: profile, startingOn: start)
        let decision = PlanAdaptation.Decision(hold: false, limit: 0.15, reason: nil)
        // Week 6 is a normal week held back by the 10% limit.
        let more = try XCTUnwrap(generator.adaptedOutline(outline, from: 5, decision: decision, profile: profile))
        XCTAssertGreaterThan(more.weeks[5].runVolumeMeters, outline.weeks[5].runVolumeMeters)
        let recent = more.weeks[2..<5].map(\.runVolumeMeters).max() ?? 0
        XCTAssertLessThanOrEqual(more.weeks[5].runVolumeMeters, recent * 1.15 + 1)
    }

    func testOlderPlansAreLeftAlone() {
        var outline = generator.makeOutline(for: profile, startingOn: start)
        for i in outline.weeks.indices { outline.weeks[i].base = nil }
        XCTAssertNil(generator.adaptedOutline(outline, from: 5, decision: .init(hold: true, limit: nil, reason: nil), profile: profile))
    }

    func testHeavyWeekMainLiftsAreHeavierForFewerReps() throws {
        let outline = generator.makeOutline(for: profile, startingOn: start)
        // Programme week 3 is a heavy gym week.
        XCTAssertEqual(outline.weeks[2].programmeWeek, 3)
        let normal = try XCTUnwrap(generator.generateWeek(1, outline: outline, profile: profile))
        let heavy = try XCTUnwrap(generator.generateWeek(2, outline: outline, profile: profile))
        let legsNormal = try XCTUnwrap(normal.sessions.first { $0.title == "Legs" }?.strength)
        let legsHeavy = try XCTUnwrap(heavy.sessions.first { $0.title == "Legs" }?.strength)
        for (a, b) in zip(legsNormal.exercises, legsHeavy.exercises) where a.role == .main && (a.weightKg ?? 0) > 0 {
            XCTAssertEqual(b.isHeavy, true, a.name)
            XCTAssertGreaterThan(b.weightKg ?? 0, a.weightKg ?? 0, a.name)
            XCTAssertEqual(b.repRange.upper, a.repRange.lower, a.name)
        }
        for exercise in legsHeavy.exercises where exercise.role == .accessory {
            XCTAssertNil(exercise.isHeavy)
        }
        XCTAssertTrue(heavy.notes.contains { $0.contains("Heavy gym week") })
    }

    func testTopUpRunNeverCostsAGymSession() {
        let outline = generator.makeOutline(for: profile, startingOn: start)
        for index in outline.weeks.indices {
            guard let week = generator.generateWeek(index, outline: outline, profile: profile) else { continue }
            let target = outline.weeks[index]
            let lifts = week.sessions.filter { $0.kind.discipline == .strength }.count
            let gym = TestSupport.bundledTemplates.programmes.programme(for: .faster10k)?.week(target.programmeWeek ?? 0)?.strength
            if target.isPostProgrammeRecovery != true, gym != "none" {
                XCTAssertEqual(lifts, 5, "Week \(index + 1) keeps all five gym sessions")
            }
            // At most one run and one gym session a day.
            let byDay = Dictionary(grouping: week.sessions, by: { calendar.startOfDay(for: $0.date) })
            for (_, sessions) in byDay {
                XCTAssertLessThanOrEqual(sessions.filter { $0.kind.discipline == .run }.count, 1)
                XCTAssertLessThanOrEqual(sessions.filter { $0.kind.discipline == .strength }.count, 1)
            }
        }
    }

    func testLongRunsBuildSteadily() {
        var half = profile
        half.goal = .halfMarathon
        let outline = generator.makeOutline(for: half, startingOn: start)
        var longs: [Double?] = []
        for index in outline.weeks.indices {
            let week = generator.generateWeek(index, outline: outline, profile: half)
            longs.append(week?.sessions.first { $0.kind == .run(.long) && !$0.summary.contains("time trial") }?.estimatedDistanceMeters)
        }
        for (i, long) in longs.enumerated() {
            guard let long, let recent = longs[max(0, i - 6)..<i].compactMap({ $0 }).suffix(3).max() else { continue }
            XCTAssertLessThanOrEqual(long, max(recent * 1.15, recent + 1500) + 300, "Week \(i + 1): \(long) after \(recent)")
        }
        // Week 9's programme long run is 18 km: kept short of it, with a note saying why.
        let nine = generator.generateWeek(8, outline: outline, profile: half)
        XCTAssertTrue(nine?.notes.contains { $0.contains("builds steadily") } ?? false)
    }

    func testHalfWithoutARaceEndsWithA10KTimeTrial() throws {
        var half = profile
        half.goal = .halfMarathon
        let outline = generator.makeOutline(for: half, startingOn: start)
        let raceWeek = try XCTUnwrap(outline.weeks.firstIndex { $0.programmeWeek == 12 })
        let week = try XCTUnwrap(generator.generateWeek(raceWeek, outline: outline, profile: half))
        let trial = try XCTUnwrap(week.sessions.first { $0.summary.contains("time trial") })
        XCTAssertTrue(trial.summary.hasPrefix("10K time trial"), trial.summary)
        XCTAssertEqual(trial.estimatedDistanceMeters ?? 0, 10000, accuracy: 1)
        // Run at 10K pace, not half-marathon pace.
        let zones = PaceZones(profile: half)
        XCTAssertEqual(trial.runStructure?.segments.first?.targetPace, zones.range(for: .tenK))
    }
}

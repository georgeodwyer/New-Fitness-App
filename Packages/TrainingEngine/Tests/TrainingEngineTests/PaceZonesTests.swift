import XCTest
@testable import TrainingEngine

final class PaceZonesTests: XCTestCase {
    func testVDOTMatchesDanielsTable() {
        // Daniels: a 20:00 5k is a VDOT of ~49.8.
        let vdot = PaceZones.vdot(for: RaceResult(distanceMeters: 5000, timeSeconds: 20 * 60))
        XCTAssertEqual(vdot, 49.8, accuracy: 0.3)
    }

    func testThresholdPaceForTwentyMinute5k() {
        let zones = PaceZones(race: RaceResult(distanceMeters: 5000, timeSeconds: 20 * 60))
        let threshold = zones.range(for: .threshold)
        // Daniels T-pace for VDOT 50 is ~4:15/km.
        XCTAssertEqual(threshold.fastest.secondsPerKm, 254, accuracy: 4)
        XCTAssertEqual(threshold.slowest.secondsPerKm, 261, accuracy: 4)
    }

    func testZonesAreOrderedSlowToFast() {
        let zones = PaceZones(race: RaceResult(distanceMeters: 10000, timeSeconds: 50 * 60))
        let order: [PaceZone] = [.easy, .marathon, .threshold, .interval, .repetition]
        for (slower, faster) in zip(order, order.dropFirst()) {
            XCTAssertGreaterThan(zones.typicalPace(for: slower).secondsPerKm, zones.typicalPace(for: faster).secondsPerKm,
                                 "\(slower) should be slower than \(faster)")
        }
    }

    func testRacePaceZonesSitInOrder() {
        let zones = PaceZones(race: RaceResult(distanceMeters: 5000, timeSeconds: 20 * 60))
        // 5K pace for a 20:00 5K is 4:00/km.
        XCTAssertEqual(zones.typicalPace(for: .fiveK).secondsPerKm, 240, accuracy: 1)
        let order: [PaceZone] = [.easy, .steady, .marathon, .halfMarathon, .threshold, .tenK, .fiveK, .repetition]
        for (slower, faster) in zip(order, order.dropFirst()) {
            XCTAssertGreaterThan(zones.typicalPace(for: slower).secondsPerKm, zones.typicalPace(for: faster).secondsPerKm,
                                 "\(slower) should be slower than \(faster)")
        }
        // Steady is 10–20 s/km slower than marathon pace.
        let gap = zones.typicalPace(for: .steady).secondsPerKm - zones.typicalPace(for: .marathon).secondsPerKm
        XCTAssertEqual(gap, 15, accuracy: 0.5)
    }

    func testDefaultZonesWhenNoRaceTime() {
        let beginner = PaceZones(profile: TestSupport.profile(running: .beginner, race: nil))
        let advanced = PaceZones(profile: TestSupport.profile(running: .advanced, race: nil))
        XCTAssertLessThan(beginner.vdot, advanced.vdot)
        XCTAssertEqual(beginner.vdot, PaceZones.vdot(for: RaceResult(distanceMeters: 5000, timeSeconds: 33 * 60)), accuracy: 0.001)
    }

    func testRacePredictionRoundTripsAndScales() {
        let race = RaceResult(distanceMeters: 5000, timeSeconds: 20 * 60)
        let zones = PaceZones(race: race)
        XCTAssertEqual(zones.predictedTime(distanceMeters: 5000), 1200, accuracy: 2)
        // Daniels equivalent 10k for VDOT ~50 is ~41:30.
        XCTAssertEqual(zones.predictedTime(distanceMeters: 10000), 41.5 * 60, accuracy: 45)
    }

    private func halfProfile(race: Double, goal: Double?) -> AthleteProfile {
        AthleteProfile(runningExperience: .intermediate, recentRace: RaceResult(distanceMeters: 5000, timeSeconds: race),
                       liftingExperience: .intermediate, goal: .halfMarathon, trainingDays: [.monday, .wednesday, .saturday],
                       equipment: .fullGym, goalTimeSeconds: goal)
    }

    func testGoalTimeSetsRacePaceAndIntervals() {
        // Goal 1:40:00 for the half: 4:44 /km. Intervals about 5% faster: ~4:30 /km.
        let zones = PaceZones(profile: halfProfile(race: 22 * 60 + 30, goal: 100 * 60))
        let goalPerKm = 6000 / 21.0975
        let race = zones.range(for: .halfMarathon)
        XCTAssertEqual((race.fastest.secondsPerKm + race.slowest.secondsPerKm) / 2, goalPerKm, accuracy: 0.5)
        let interval = zones.range(for: .interval)
        XCTAssertEqual((interval.fastest.secondsPerKm + interval.slowest.secondsPerKm) / 2, goalPerKm * 0.95, accuracy: 0.5)
        // Easy pace still comes from current fitness.
        XCTAssertEqual(zones.range(for: .easy), PaceZones.fitness(halfProfile(race: 22 * 60 + 30, goal: nil)).range(for: .easy))
    }

    func testNoGoalTimeKeepsFitnessPaces() {
        let profile = halfProfile(race: 22 * 60 + 30, goal: nil)
        XCTAssertEqual(PaceZones(profile: profile), PaceZones.fitness(profile))
        XCTAssertNil(GoalTime(profile: profile))
    }

    func testOptimisticGoalIsFlagged() {
        let predicted = PaceZones.fitness(halfProfile(race: 22 * 60 + 30, goal: nil)).predictedTime(distanceMeters: 21097.5)
        let realistic = GoalTime(profile: halfProfile(race: 22 * 60 + 30, goal: predicted * 0.97))!
        XCTAssertFalse(realistic.isTooOptimistic)
        let optimistic = GoalTime(profile: halfProfile(race: 22 * 60 + 30, goal: predicted * 0.92))!
        XCTAssertTrue(optimistic.isTooOptimistic)
        XCTAssertEqual(optimistic.fasterThanPredicted, 0.08, accuracy: 0.001)
        XCTAssertEqual(optimistic.realisticRange.upperBound, predicted, accuracy: 0.01)
    }
}
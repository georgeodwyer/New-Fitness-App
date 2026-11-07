import XCTest
@testable import TrainingEngine

final class FunctionalTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 3_000_000)
    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    private let run = FunctionalStation(kind: .run, target: .meters(1000), pace: .fixed(.single(Pace(secondsPerKm: 240))))
    private let ski = FunctionalStation(kind: .ski, target: .meters(500))
    private let rest = FunctionalStation(kind: .rest, target: .seconds(60))

    func testRoundsForTimeMoveOnWithNextAndRestsByThemselves() {
        var session = FunctionalSession(workout: FunctionalWorkout(name: "Test", format: .rounds(2), stations: [run, ski, rest]), startedAt: start)
        session.next(at: at(240), meters: 1000)       // run done
        XCTAssertEqual(session.station?.kind, .ski)
        session.next(at: at(360))                     // ski done
        XCTAssertEqual(session.station?.kind, .rest)
        XCTAssertEqual(session.remaining(at: at(390)), 30)
        session.tick(at: at(421))                     // rest over by itself
        XCTAssertEqual(session.round, 2)
        XCTAssertEqual(session.station?.kind, .run)
        session.next(at: at(660)); session.next(at: at(780)); session.tick(at: at(841))
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.splits.count, 6)
        XCTAssertEqual(session.splits[0].seconds, 240)
        XCTAssertEqual(session.splits[0].meters, 1000)
    }

    func testUndoTakesBackTheLastNext() {
        var session = FunctionalSession(workout: FunctionalWorkout(name: "Test", format: .rounds(1), stations: [run, ski]), startedAt: start)
        session.next(at: at(250))
        session.undo()
        XCTAssertEqual(session.station?.kind, .run)
        XCTAssertTrue(session.splits.isEmpty)
        XCTAssertEqual(session.phaseElapsed(at: at(260)), 260, "The run carries on from when it started")
    }

    func testIntervalsRunByTheClock() {
        // 40 s on / 20 s off, two stations, 2 rounds: 4 work periods.
        var session = FunctionalSession(workout: FunctionalWorkout(name: "Test", format: .intervals(work: 40, rest: 20, rounds: 2),
                                                                   stations: [run, ski]), startedAt: start)
        for second in 1...240 { session.tick(at: at(Double(second))) }
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.splits.count, 4)
        XCTAssertTrue(session.splits.allSatisfy { $0.seconds == 40 })
    }

    func testEMOMStartsANewStationEveryMinute() {
        var session = FunctionalSession(workout: FunctionalWorkout(name: "Test", format: .emom(every: 60, rounds: 4),
                                                                   stations: [ski, run]), startedAt: start)
        session.next(at: at(35))                      // ski done in 35 s
        XCTAssertTrue(session.isWaitingForInterval)
        session.tick(at: at(60))
        XCTAssertEqual(session.station?.kind, .run)
        for second in 61...240 { session.tick(at: at(Double(second))) }
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.splits.count, 4)
        XCTAssertEqual(session.splits[0].seconds, 35)
    }

    func testAMRAPCountsRoundsUntilTheCap() {
        var session = FunctionalSession(workout: FunctionalWorkout(name: "Test", format: .amrap(cap: 600), stations: [ski, run]), startedAt: start)
        var t = 0.0
        while !session.isFinished, t < 600 {
            t += 100
            session.next(at: at(t))
            session.tick(at: at(t))
        }
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.roundsDone, 3)
    }

    func testHyroxSimulation() {
        let race = HyroxSimulation.workout(division: .proMen)
        XCTAssertEqual(race.stations.count, 16)
        XCTAssertEqual(race.stations.filter { $0.kind == .run }.count, 8)
        XCTAssertEqual(race.stations.first { $0.kind == .wallBalls }?.target, .reps(100))
        XCTAssertEqual(race.stations.first { $0.kind == .sledPush }?.weightKg, 202)
        XCTAssertEqual(HyroxSimulation.workout(division: .openWomen).stations.first { $0.kind == .wallBalls }?.weightKg, 4)
    }

    func testRunPaceFromAZoneFollowsFitness() {
        let zones = PaceZones(race: RaceResult(distanceMeters: 5000, timeSeconds: 1200))
        XCTAssertEqual(FunctionalPace.zone(.interval).range(zones: zones), zones.range(for: .interval))
        XCTAssertEqual(FunctionalPace.fixed(.single(Pace(secondsPerKm: 240))).range(zones: zones).fastest.secondsPerKm, 240)
        XCTAssertEqual(FunctionalTarget.seconds(60).text, "1 min")
        XCTAssertEqual(FunctionalTarget.meters(1000).text, "1 km")
    }

    func testRecordAddsUpRunsAndTimeByKind() {
        let start = Date(timeIntervalSince1970: 0)
        let workout = FunctionalWorkout(name: "Mini", format: .rounds(2), stations: [
            FunctionalStation(kind: .run, target: .meters(400)),
            FunctionalStation(kind: .wallBalls, target: .reps(20))
        ])
        var session = FunctionalSession(workout: workout, startedAt: start)
        session.next(at: start.addingTimeInterval(90), meters: 410)
        session.next(at: start.addingTimeInterval(150))
        session.next(at: start.addingTimeInterval(245), meters: 395)
        session.next(at: start.addingTimeInterval(300))
        XCTAssertTrue(session.isFinished)
        let record = FunctionalRecord(session: session)
        XCTAssertEqual(record.runMeters, 805)
        XCTAssertEqual(record.timeByKind.first?.kind, .run)
        XCTAssertEqual(record.timeByKind.first?.seconds, 185)
        XCTAssertEqual(record.lines().first, "R1 Run 400 m  1:30")
        XCTAssertEqual(Pace(secondsPerKm: 240).kilometresPerHour, 15)
    }
}

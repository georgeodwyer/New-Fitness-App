import XCTest
@testable import TrainingEngine

final class PaceTests: XCTestCase {
    func testPaceFromSpeed() throws {
        let pace = try XCTUnwrap(Pace(metersPerSecond: 1000.0 / 300.0))
        XCTAssertEqual(pace.secondsPerKm, 300, accuracy: 0.001)
    }

    func testStandstillHasNoPace() {
        XCTAssertNil(Pace(metersPerSecond: 0))
    }

    func testMilePace() {
        let pace = Pace(secondsPerKm: 300)
        XCTAssertEqual(pace.secondsPerMile, 482.8, accuracy: 0.1)
    }

    func testRangeOrdersEnds() {
        let range = PaceRange(fastest: Pace(secondsPerKm: 300), slowest: Pace(secondsPerKm: 270))
        XCTAssertEqual(range.fastest.secondsPerKm, 270)
        XCTAssertEqual(range.slowest.secondsPerKm, 300)
    }

    func testRangePositionWithTolerance() {
        let range = PaceRange(fastest: Pace(secondsPerKm: 270), slowest: Pace(secondsPerKm: 285))
        XCTAssertEqual(range.position(of: Pace(secondsPerKm: 260)), .tooFast)
        XCTAssertEqual(range.position(of: Pace(secondsPerKm: 260), toleranceSecondsPerKm: 10), .onTarget)
        XCTAssertEqual(range.position(of: Pace(secondsPerKm: 280)), .onTarget)
        XCTAssertEqual(range.position(of: Pace(secondsPerKm: 300), toleranceSecondsPerKm: 10), .tooSlow)
    }
}

final class UnitsTests: XCTestCase {
    func testFormatMinutesSeconds() {
        XCTAssertEqual(Units.formatMinutesSeconds(282), "4:42")
        XCTAssertEqual(Units.formatMinutesSeconds(59.6), "1:00")
        XCTAssertEqual(Units.formatMinutesSeconds(3725), "1:02:05")
    }

    func testFormatDistance() {
        XCTAssertEqual(Units.formatDistance(meters: 4820, units: .metric), "4.82")
        XCTAssertEqual(Units.formatDistance(meters: 1609.344, units: .imperial), "1.00")
    }

    func testFormatWeight() {
        XCTAssertEqual(Units.formatWeight(kg: 105, units: .metric), "105")
        XCTAssertEqual(Units.formatWeight(kg: 102.5, units: .metric), "102.5")
        XCTAssertEqual(Units.formatWeight(kg: 100, units: .imperial), "220.5")
    }

    func testWeightRoundTrip() {
        XCTAssertEqual(Units.lbToKg(Units.kgToLb(80)), 80, accuracy: 0.0001)
    }
}

final class DomainCodingTests: XCTestCase {
    func testSessionKindRoundTrip() throws {
        let kinds: [SessionKind] = [.run(.intervals), .strength(.lower), .crossTraining, .mobility]
        let data = try JSONEncoder().encode(kinds)
        XCTAssertEqual(try JSONDecoder().decode([SessionKind].self, from: data), kinds)
    }

    func testRunStructureRoundTrip() throws {
        let zone = PaceRange(fastest: Pace(secondsPerKm: 240), slowest: Pace(secondsPerKm: 250))
        let structure = RunStructure(segments: [
            RunSegment(kind: .warmUp, length: .duration(seconds: 600)),
            RunSegment(kind: .work, length: .distance(meters: 800), targetPace: zone),
            RunSegment(kind: .recovery, length: .duration(seconds: 90)),
            RunSegment(kind: .coolDown, length: .duration(seconds: 600))
        ])
        let data = try JSONEncoder().encode(structure)
        XCTAssertEqual(try JSONDecoder().decode(RunStructure.self, from: data), structure)
    }

    func testProfileSortsTrainingDays() {
        let profile = AthleteProfile(
            runningExperience: .intermediate,
            liftingExperience: .beginner,
            goal: .balancedHybrid,
            trainingDays: [.friday, .monday, .wednesday],
            equipment: .fullGym
        )
        XCTAssertEqual(profile.trainingDays, [.monday, .wednesday, .friday])
    }

    func testQualityAndLowerBodyFlags() {
        XCTAssertTrue(RunSessionType.intervals.isQuality)
        XCTAssertFalse(RunSessionType.easy.isQuality)
        XCTAssertTrue(StrengthFocus.lower.loadsLowerBody)
        XCTAssertFalse(StrengthFocus.upper.loadsLowerBody)
    }
}

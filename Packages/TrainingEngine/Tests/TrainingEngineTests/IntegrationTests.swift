import XCTest
@testable import TrainingEngine

final class HeartRateMeasurementTests: XCTestCase {
    func testUInt8HeartRate() {
        let m = HeartRateMeasurement.parse(Data([0x00, 72]))
        XCTAssertEqual(m, HeartRateMeasurement(bpm: 72))
        XCTAssertEqual(m?.isUsable, true)
    }

    func testUInt16HeartRate() {
        // 0x012C = 300 → implausible, parsed but not usable.
        let m = HeartRateMeasurement.parse(Data([0x01, 0x2C, 0x01]))
        XCTAssertEqual(m?.bpm, 300)
        XCTAssertEqual(m?.isUsable, false)
        XCTAssertEqual(HeartRateMeasurement.parse(Data([0x01, 0x9B, 0x00]))?.bpm, 155)
    }

    func testSensorContact() {
        XCTAssertEqual(HeartRateMeasurement.parse(Data([0x06, 140]))?.sensorContact, true)
        let noContact = HeartRateMeasurement.parse(Data([0x04, 140]))
        XCTAssertEqual(noContact?.sensorContact, false)
        XCTAssertEqual(noContact?.isUsable, false)
        XCTAssertNil(HeartRateMeasurement.parse(Data([0x02, 140]))?.sensorContact, "Contact bit without 'supported' means unknown")
    }

    func testEnergyAndRRIntervals() {
        // flags: UInt8 HR + energy + RR; HR 150; energy 0x0102 = 258 kJ; RR 1024 (1.0 s) and 512 (0.5 s).
        let m = HeartRateMeasurement.parse(Data([0x18, 150, 0x02, 0x01, 0x00, 0x04, 0x00, 0x02]))
        XCTAssertEqual(m?.bpm, 150)
        XCTAssertEqual(m?.energyExpendedKJ, 258)
        XCTAssertEqual(m?.rrIntervals, [1.0, 0.5])
    }

    func testMalformedData() {
        XCTAssertNil(HeartRateMeasurement.parse(Data()))
        XCTAssertNil(HeartRateMeasurement.parse(Data([0x00])))
        XCTAssertNil(HeartRateMeasurement.parse(Data([0x01, 0x50])), "UInt16 flag with one byte")
        // A trailing odd RR byte is ignored.
        XCTAssertEqual(HeartRateMeasurement.parse(Data([0x10, 120, 0x00, 0x04, 0x01]))?.rrIntervals, [1.0])
    }
}

final class RestingHeartRateTests: XCTestCase {
    func testNeedsAWeekOfHistory() {
        XCTAssertNil(RestingHeartRateSignal.assess(today: 60, history: [50, 51, 52]))
    }

    func testElevatedAgainstMedian() {
        let history: [Double] = [50, 51, 52, 50, 49, 51, 80] // one outlier barely moves the median
        let signal = RestingHeartRateSignal.assess(today: 58, history: history)
        XCTAssertEqual(signal?.baseline, 51)
        XCTAssertEqual(signal?.isElevated, true)
        XCTAssertEqual(signal?.description, "58 bpm · 7 above your usual")
        XCTAssertEqual(RestingHeartRateSignal.assess(today: 53, history: history)?.isElevated, false)
        XCTAssertEqual(RestingHeartRateSignal.assess(today: 48, history: history)?.description, "48 bpm · 3 below your usual")
    }

    func testCheckInUsesElevatedRestingHeartRate() {
        let okay = RecoveryCheckIn(sleep: 3, soreness: 3, energy: 3) // readiness 0.5
        XCTAssertFalse(okay.isPoor)
        XCTAssertTrue(RecoveryCheckIn(sleep: 3, soreness: 3, energy: 3, restingHeartRateElevated: true).isPoor)
        // Feeling great overrides a raised resting HR on its own.
        XCTAssertFalse(RecoveryCheckIn(sleep: 5, soreness: 1, energy: 5, restingHeartRateElevated: true).isPoor)
    }
}

final class GPXBuilderTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_760_000_000) // 2025-10-09T08:53:20Z

    func testBuildsTrackWithTimesAndHeartRate() {
        let route = [
            RoutePoint(latitude: 51.5073509, longitude: -0.1657, elapsed: 0),
            RoutePoint(latitude: 51.508, longitude: -0.166, elapsed: 10),
            RoutePoint(latitude: 51.509, longitude: -0.167, elapsed: 60)
        ]
        let hr = [HeartRateSample(elapsed: 1, bpm: 120.4), HeartRateSample(elapsed: 11, bpm: 131)]
        let gpx = GPXBuilder.gpx(name: "Easy run & strides", start: start, route: route, heartRate: hr)

        XCTAssertTrue(gpx.hasPrefix(#"<?xml version="1.0" encoding="UTF-8"?>"#))
        XCTAssertTrue(gpx.contains("<name>Easy run &amp; strides</name>"))
        XCTAssertTrue(gpx.contains(#"<trkpt lat="51.5073509" lon="-0.1657"><time>2025-10-09T08:53:20Z</time>"#))
        XCTAssertTrue(gpx.contains("<time>2025-10-09T08:53:30Z</time><extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>131</gpxtpx:hr>"))
        XCTAssertTrue(gpx.contains("<gpxtpx:hr>120</gpxtpx:hr>"))
        // The last point is 49 s from any HR sample, so it has none.
        XCTAssertTrue(gpx.contains("<time>2025-10-09T08:54:20Z</time></trkpt>"))
        XCTAssertEqual(gpx.components(separatedBy: "<trkpt ").count - 1, 3)
        XCTAssertTrue(gpx.hasSuffix("</gpx>\n"))
    }

    func testNearestHeartRate() {
        let samples = [HeartRateSample(elapsed: 0, bpm: 100), HeartRateSample(elapsed: 20, bpm: 140)]
        XCTAssertEqual(GPXBuilder.nearestHeartRate(to: 8, in: samples), 100)
        XCTAssertEqual(GPXBuilder.nearestHeartRate(to: 12, in: samples), 140)
        XCTAssertEqual(GPXBuilder.nearestHeartRate(to: 34, in: samples), 140)
        XCTAssertNil(GPXBuilder.nearestHeartRate(to: 40, in: samples))
        XCTAssertNil(GPXBuilder.nearestHeartRate(to: 5, in: []))
    }
}

final class ExternalWorkoutTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    private func workout(_ kind: ExternalWorkout.Kind, startMinutes: Double, minutes: Double, hr: Double? = nil) -> ExternalWorkout {
        let start = base.addingTimeInterval(startMinutes * 60)
        return ExternalWorkout(id: UUID(), start: start, end: start.addingTimeInterval(minutes * 60), kind: kind, name: "x", averageHeartRate: hr)
    }

    func testLoadUsesTypicalEffortWithoutHeartRate() {
        let entries = ExternalWorkouts.loadEntries([workout(.cycling, startMinutes: 0, minutes: 60)], excluding: [])
        XCTAssertEqual(entries, [LoadEntry(date: base, discipline: .crossTraining, load: 240)])
    }

    func testEffortFromHeartRate() {
        XCTAssertEqual(workout(.run, startMinutes: 0, minutes: 30, hr: 114).estimatedEffort(maxHeartRate: 190), 3) // 60%
        XCTAssertEqual(workout(.run, startMinutes: 0, minutes: 30, hr: 180.5).estimatedEffort(maxHeartRate: 190), 9) // 95%
        XCTAssertEqual(workout(.run, startMinutes: 0, minutes: 30, hr: 80).estimatedEffort(maxHeartRate: 190), 1)
        XCTAssertEqual(workout(.run, startMinutes: 0, minutes: 30, hr: 150).estimatedEffort(maxHeartRate: nil), 5)
    }

    func testSkipsWorkoutsAlreadyRecordedAndVeryShortOnes() {
        let recorded = [DateInterval(start: base, duration: 40 * 60)]
        let entries = ExternalWorkouts.loadEntries([
            workout(.run, startMinutes: 2, minutes: 36),   // same run recorded on the Watch
            workout(.strength, startMinutes: 30, minutes: 60), // overlaps 10 of 60 min: separate session
            workout(.walking, startMinutes: 200, minutes: 3)   // too short to count
        ], excluding: recorded)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.discipline, .strength)
    }
}

final class RunEngineHeartRateTests: XCTestCase {
    func testHeartRateSamplesAreThinnedToEveryFiveSeconds() {
        var engine = RunEngine(structure: nil)
        let start = Date(timeIntervalSince1970: 1_000)
        _ = engine.start(at: start)
        for second in 0...20 {
            let now = start.addingTimeInterval(Double(second))
            _ = engine.tick(at: now)
            engine.addHeartRate(130 + Double(second), at: now)
        }
        let samples = engine.summary().heartRateSamples
        XCTAssertEqual(samples.map(\.elapsed), [0, 5, 10, 15, 20])
        XCTAssertEqual(samples.last?.bpm, 150)
        XCTAssertEqual(engine.summary().maxHeartRate, 150)
    }
}

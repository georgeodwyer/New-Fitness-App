import XCTest
@testable import TrainingEngine

final class FTMSTests: XCTestCase {
    func testReadsSpeedDistanceAndIncline() throws {
        // Flags: speed (bit 0 clear), total distance (bit 2), inclination (bit 3), elapsed time (bit 10).
        let flags: UInt16 = (1 << 2) | (1 << 3) | (1 << 10)
        var bytes: [UInt8] = [UInt8(flags & 0xFF), UInt8(flags >> 8)]
        bytes += [0xDC, 0x05]             // 15.00 km/h
        bytes += [0xC4, 0x09, 0x00]       // 2500 m
        bytes += [0x0F, 0x00, 0x00, 0x00] // 1.5 % incline, ramp angle 0
        bytes += [0x2C, 0x01]             // 300 s
        let reading = try XCTUnwrap(FTMS.reading(bytes))
        XCTAssertEqual(try XCTUnwrap(reading.speedKmh), 15, accuracy: 0.001)
        XCTAssertEqual(reading.totalMeters, 2500)
        XCTAssertEqual(try XCTUnwrap(reading.inclinePercent), 1.5, accuracy: 0.001)
        XCTAssertEqual(reading.elapsedSeconds, 300)
    }

    func testMoreDataFlagMeansNoSpeed() throws {
        let reading = try XCTUnwrap(FTMS.reading([0x05, 0x00, 0x10, 0x27, 0x00]))  // bit 0 set + distance
        XCTAssertNil(reading.speedKmh)
        XCTAssertEqual(reading.totalMeters, 10_000)
        XCTAssertNil(FTMS.reading([0x00]))
    }

    func testNegativeIncline() throws {
        let reading = try XCTUnwrap(FTMS.reading([0x08, 0x00, 0x00, 0x00, 0xF6, 0xFF, 0x00, 0x00]))  // −1.0 %
        XCTAssertEqual(try XCTUnwrap(reading.inclinePercent), -1.0, accuracy: 0.001)
    }

    func testCommands() {
        XCTAssertEqual(FTMS.setSpeed(kilometresPerHour: 12.5), [0x02, 0xE2, 0x04])
        XCTAssertEqual(FTMS.setIncline(percent: -2), [0x03, 0xEC, 0xFF])
        XCTAssertEqual(FTMS.pause, [0x08, 0x02])
        XCTAssertEqual(FTMS.stop, [0x08, 0x01])
        XCTAssertEqual(FTMS.response([0x80, 0x02, 0x01])?.succeeded, true)
        XCTAssertEqual(FTMS.response([0x80, 0x00, 0x05])?.succeeded, false)
    }

    func testSpeedForATargetNeverGoesFaster() throws {
        // 4:00–4:10 /km: middle 4:05 ≈ 14.7 km/h, fast end 15.0 km/h.
        let target = PaceRange(fastest: Pace(secondsPerKm: 240), slowest: Pace(secondsPerKm: 250))
        let range = try XCTUnwrap(FTMS.speedRange([0x64, 0x00, 0xD0, 0x07, 0x0A, 0x00]))  // 1–20 km/h in 0.1
        XCTAssertEqual(range.maximum, 20)
        let speed = FTMS.speed(for: target, supported: range)
        XCTAssertEqual(speed, 14.7, accuracy: 0.001)
        XCTAssertLessThanOrEqual(speed, target.fastest.kilometresPerHour)
        // Capped at what the treadmill can do.
        let sprint = PaceRange(fastest: Pace(secondsPerKm: 150), slowest: Pace(secondsPerKm: 155))
        XCTAssertEqual(FTMS.speed(for: sprint, supported: range), 20)
    }
}

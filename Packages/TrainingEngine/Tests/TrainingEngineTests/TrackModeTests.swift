import XCTest
@testable import TrainingEngine

final class TrackModeTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 2_000_000)
    /// A track in Battersea Park, turned 30° from east.
    private let track = TrackFit(latitude: 51.4795, longitude: -0.1560, angle: 0.52, fittedRadius: 36.8, residual: 0)

    func testLaneLengths() {
        XCTAssertEqual(TrackGeometry.lapLength(lane: 1), 400, accuracy: 0.1)
        XCTAssertEqual(TrackGeometry.lapLength(lane: 2), 407.0, accuracy: 0.2)
        XCTAssertEqual(TrackGeometry.lapLength(lane: 8), 400 + 2 * .pi * (1.22 * 7 - 0.1), accuracy: 0.1)
    }

    func testProjectionRoundTrips() {
        for position in stride(from: 0.0, to: 400, by: 13) {
            let point = track.coordinate(atPosition: position, lane: 1)
            let back = track.project(latitude: point.latitude, longitude: point.longitude, lane: 1)
            XCTAssertEqual(back.position, position, accuracy: 0.05)
            XCTAssertEqual(back.offset, 0, accuracy: 0.05)
        }
    }

    /// GPS that wanders a few metres either side of lane 1, one fix a second at `speed`.
    private func noisyLaps(seconds: Int, speed: Double = 4.5, noise: Double = 4, lane: Int = 1) -> [LocationSample] {
        var generator = SeededGenerator(seed: 7)
        return (0..<seconds).map { second in
            let truth = track.coordinate(atPosition: Double(second) * speed, lane: lane)
            let dLat = Double.random(in: -noise...noise, using: &generator) / 110_540
            let dLon = Double.random(in: -noise...noise, using: &generator) / (111_320 * cos(truth.latitude * .pi / 180))
            return LocationSample(timestamp: start.addingTimeInterval(Double(second)), latitude: truth.latitude + dLat,
                                  longitude: truth.longitude + dLon, horizontalAccuracy: 5, speed: speed)
        }
    }

    func testFindsTheTrackFromALapOfNoisyGPS() {
        let samples = noisyLaps(seconds: 100)
        let fit = TrackDetector.fit(samples.map { ($0.latitude, $0.longitude) })
        XCTAssertNotNil(fit)
        XCTAssertLessThan(fit?.residual ?? 99, 5)
    }

    func testAStraightRoadIsNotATrack() {
        let samples = (0..<120).map { second in
            LocationSample(timestamp: start.addingTimeInterval(Double(second)), latitude: 51.47 + Double(second) * 4 / 110_540,
                           longitude: -0.15, horizontalAccuracy: 5, speed: 4)
        }
        XCTAssertNil(TrackDetector.fit(samples.map { ($0.latitude, $0.longitude) }))
    }

    func testTrackModeMeasuresTheLaneNotTheGPSWobble() {
        let samples = noisyLaps(seconds: 100 + 178) // a lap to find the track, then 2 laps (800 m at 4.5 m/s)
        var gps = RunEngine(structure: nil)
        var onTrack = RunEngine(structure: nil)
        _ = gps.start(at: start)
        _ = onTrack.start(at: start)
        for (index, sample) in samples.enumerated() {
            _ = gps.addLocation(sample)
            _ = onTrack.addLocation(sample)
            if index == 99 {
                XCTAssertTrue(onTrack.looksLikeTrack(), "Suggested after a lap")
                onTrack.useTrack(lane: 1)
            }
        }
        XCTAssertEqual(onTrack.snapshot().trackLane, 1)
        let lapsOnTrack = onTrack.snapshot().trackLaps ?? 0
        XCTAssertEqual(lapsOnTrack * 400, 177 * 4.5, accuracy: 12, "Two laps on the track measure close to 800 m")
        // Plain GPS adds distance from the wobble.
        XCTAssertGreaterThan(gps.summary().distanceMeters, onTrack.summary().distanceMeters)
        XCTAssertEqual(onTrack.summary().trackLane, 1)
    }

    func testRunningOffTheTrackGoesBackToGPS() {
        var engine = RunEngine(structure: nil)
        _ = engine.start(at: start)
        let laps = noisyLaps(seconds: 100, noise: 2)
        for sample in laps { _ = engine.addLocation(sample) }
        engine.useTrack(lane: 1)
        XCTAssertNotNil(engine.snapshot().trackLane)
        // Then off down a road, 200 m+ away.
        let last = laps.last!
        for second in 1...30 {
            _ = engine.addLocation(LocationSample(timestamp: last.timestamp.addingTimeInterval(Double(second)),
                                                  latitude: last.latitude + Double(second) * 8 / 110_540, longitude: last.longitude,
                                                  horizontalAccuracy: 5, speed: 4))
        }
        XCTAssertNil(engine.snapshot().trackLane)
    }
}

/// Repeatable random numbers for tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

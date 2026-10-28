import XCTest
@testable import TrainingEngine

final class WatchScreensTests: XCTestCase {
    private func snapshot(heartRate: Double? = 150, status: PaceRange.Position? = .onTarget) -> RunSnapshot {
        RunSnapshot(elapsedSeconds: 1998, distanceMeters: 6420, currentPace: Pace(secondsPerKm: 312), averagePace: Pace(secondsPerKm: 311),
                    segmentIndex: 3, segment: RunSegment(kind: .work, length: .distance(meters: 800),
                                                         targetPace: PaceRange(fastest: Pace(secondsPerKm: 228), slowest: Pace(secondsPerKm: 238))),
                    nextSegment: RunSegment(kind: .recovery, length: .duration(seconds: 90), label: "Recovery jog"),
                    segmentProgress: 0.5, segmentRemaining: .distance(meters: 420), paceStatus: status,
                    timeInTargetSeconds: 0, targetedSeconds: 0, heartRate: heartRate, isPaused: false,
                    isStructureComplete: false, lastCue: nil, gpsAvailable: true,
                    lapNumber: 2, lapElapsedSeconds: 191, lapDistanceMeters: 620)
    }

    private let zones = HeartRateZones(maxHeartRate: 190, maxSource: .custom, starts: [95, 114, 133, 152, 171], isCustom: false)

    func testStandardScreens() {
        let standard = WatchScreenSettings.standard
        XCTAssertEqual(standard.enabledScreens.map(\.name), ["Pace & distance", "Heart rate"])
        XCTAssertTrue(standard.screens.allSatisfy { $0.metrics.count == $0.layout.slotCount })
        XCTAssertEqual(WatchScreenSettings.decode(standard.encoded()), standard)
    }

    func testChangingLayoutKeepsMetricsThatFit() {
        var screen = WatchScreen(name: "Test", layout: .oneFour, metrics: [.heartRate, .pace, .time, .distance, .cadence])
        screen.setLayout(.oneTwo)
        XCTAssertEqual(screen.metrics, [.heartRate, .pace, .time])
        screen.setLayout(.sixSmall)
        XCTAssertEqual(screen.slots.count, 6)
        XCTAssertEqual(Array(screen.slots.prefix(3)), [.heartRate, .pace, .time])
    }

    func testReadings() {
        let samples = (0..<120).map { HeartRateSample(elapsed: Double($0) * 5, bpm: 140) }
        let input = WatchMetricInputs(snapshot: snapshot(), structure: RunStructure(segments: [
            RunSegment(kind: .warmUp, length: .distance(meters: 1500)),
            RunSegment(kind: .work, length: .distance(meters: 800)),
            RunSegment(kind: .recovery, length: .duration(seconds: 90)),
            RunSegment(kind: .work, length: .distance(meters: 800)),
            RunSegment(kind: .recovery, length: .duration(seconds: 90)),
            RunSegment(kind: .work, length: .distance(meters: 800)),
        ]), units: .metric, heartRateSamples: samples, zones: zones, cadence: 171.6)
        XCTAssertEqual(WatchMetric.pace.reading(input), WatchMetricReading("5:12", unit: "/km", tone: .good))
        XCTAssertEqual(WatchMetric.distance.reading(input).value, "6.42")
        XCTAssertEqual(WatchMetric.time.reading(input).value, "33:18")
        XCTAssertEqual(WatchMetric.heartRate.reading(input).zone, 3)
        XCTAssertEqual(WatchMetric.heartRateZone.reading(input).value, "Z3")
        XCTAssertEqual(WatchMetric.averageHeartRate.reading(input).value, "140")
        XCTAssertEqual(WatchMetric.stepRemaining.reading(input), WatchMetricReading("420", unit: "m"))
        XCTAssertEqual(WatchMetric.nextStep.reading(input).value, "Recovery jog")
        XCTAssertEqual(WatchMetric.repProgress.reading(input).value, "2/3")
        XCTAssertEqual(WatchMetric.lapPace.reading(input).value, "5:08")
        XCTAssertEqual(WatchMetric.targetPace.reading(input).value, "3:48–3:58")
        XCTAssertEqual(WatchMetric.cadence.reading(input).value, "172")
        XCTAssertNotEqual(WatchMetric.exertion.reading(input).value, "–")
        XCTAssertEqual(WatchMetric.calories.reading(input).value, "–", "Nothing measured yet")
    }

    func testOffTargetPaceIsAWarning() {
        let input = WatchMetricInputs(snapshot: snapshot(status: .tooSlow), units: .metric)
        XCTAssertEqual(WatchMetric.pace.reading(input).tone, .warning)
        XCTAssertEqual(WatchMetric.paceVsTarget.reading(input).value, "Too slow")
    }

    func testPlanCarriesScreensAndZones() {
        let plan = WatchPlan(generatedAt: Date(timeIntervalSince1970: 0), units: .metric, coaching: CoachingConfig(), runs: [],
                             screens: .standard, zoneStarts: zones.starts, maxHeartRate: 190)
        let decoded = WatchPlan.decode(plan.encoded())
        XCTAssertEqual(decoded?.screens, .standard)
        XCTAssertEqual(decoded?.heartRateZones?.zone(for: 160), 4)
    }
}

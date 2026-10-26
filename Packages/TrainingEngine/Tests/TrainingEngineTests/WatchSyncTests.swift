import XCTest
@testable import TrainingEngine

final class WatchSyncTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_792_049_400) // 15 Oct 2026, 07:30 UTC

    private var intervals: RunStructure {
        RunStructure(segments: [
            RunSegment(kind: .warmUp, length: .duration(seconds: 600)),
            RunSegment(kind: .work, length: .distance(meters: 400), targetPace: PaceRange(fastest: Pace(secondsPerKm: 230), slowest: Pace(secondsPerKm: 240)))
        ])
    }

    func testPlanRoundTripsAndSortsOptions() throws {
        let today = WatchRunOption(id: UUID(), source: .planned, title: "Intervals", detail: "6 × 400 m", date: now, structure: intervals,
                                   typicalEffort: 8)
        let later = WatchRunOption(id: UUID(), source: .planned, title: "Long run", date: now.addingTimeInterval(3 * 86_400))
        let soon = WatchRunOption(id: UUID(), source: .planned, title: "Easy", date: now.addingTimeInterval(86_400))
        let template = WatchRunOption(id: UUID(), source: .template, title: "Threshold 2 × 10", recordType: "tempo")
        let plan = WatchPlan(generatedAt: now, units: .imperial, coaching: CoachingConfig(paceCueDelaySeconds: 15, units: .imperial),
                             runs: [later, today, soon, template])

        let decoded = try XCTUnwrap(WatchPlan.decode(plan.encoded()))
        XCTAssertEqual(decoded, plan)
        XCTAssertEqual(decoded.version, WatchPlan.currentVersion)
        XCTAssertEqual(decoded.planned(on: now, calendar: calendar).map(\.title), ["Intervals"])
        XCTAssertEqual(decoded.upcoming(after: now, calendar: calendar).map(\.title), ["Easy", "Long run"])
        XCTAssertEqual(decoded.templates.map(\.title), ["Threshold 2 × 10"])
        XCTAssertNil(WatchPlan.decode(Data("not json".utf8)))
    }

    func testResultRoundTripsAndThinsTheRoute() throws {
        var summary = RunSummary(durationSeconds: 600, distanceMeters: 2000, averagePace: Pace(secondsPerKm: 300), splits: [],
                                 segments: [], timeInTargetSeconds: 0, targetedSeconds: 0, averageHeartRate: 150, maxHeartRate: 170,
                                 route: (0...600).map { RoutePoint(latitude: 51.5 + Double($0) * 1e-5, longitude: -0.16, elapsed: Double($0)) })
        summary.heartRateSamples = [HeartRateSample(elapsed: 5, bpm: 120)]
        let result = WatchRunResult(option: .freeRun, startedAt: now, finishedAt: now.addingTimeInterval(620), summary: summary,
                                    effort: 6, healthKitWorkoutId: UUID())
        let thinned = result.thinned(everySeconds: 5)
        XCTAssertEqual(thinned.summary.route.count, 121)
        XCTAssertEqual(thinned.summary.route.last?.elapsed, 600)
        XCTAssertEqual(thinned.summary.distanceMeters, 2000, "Totals are untouched")

        let decoded = try XCTUnwrap(WatchRunResult.decode(thinned.encoded()))
        XCTAssertEqual(decoded, thinned)
        XCTAssertEqual(decoded.option.source, .free)
        XCTAssertEqual(decoded.summary.heartRateSamples.count, 1)
    }

    func testDoubleTapModels() {
        XCTAssertTrue(WatchControlSettings.supportsDoubleTap(machine: "Watch7,1"), "Series 9")
        XCTAssertTrue(WatchControlSettings.supportsDoubleTap(machine: "Watch7,5"), "Ultra 2")
        XCTAssertTrue(WatchControlSettings.supportsDoubleTap(machine: "Watch7,10"), "Series 10")
        XCTAssertFalse(WatchControlSettings.supportsDoubleTap(machine: "Watch6,18"), "Ultra")
        XCTAssertFalse(WatchControlSettings.supportsDoubleTap(machine: "Watch6,2"), "Series 8")
        XCTAssertFalse(WatchControlSettings.supportsDoubleTap(machine: "x86_64"))
    }

    func testCrownSensitivity() throws {
        // Settings saved before sensitivity existed read as the middle level.
        let old = #"{"doubleTap":"nextOrLap","crown":"nextOrLap","crownTurn":0.25,"undoSeconds":3}"#
        let decoded = try JSONDecoder().decode(WatchControlSettings.self, from: Data(old.utf8))
        XCTAssertNil(decoded.crownSensitivity)
        XCTAssertEqual(decoded.sensitivity, 3)
        XCTAssertEqual(decoded.crownTurnsNeeded, 0.5)
        var settings = WatchControlSettings(crownSensitivity: 1)
        XCTAssertEqual(settings.crownTurnsNeeded, 1)
        XCTAssertLessThan(settings.crownWindowSeconds, WatchControlSettings(crownSensitivity: 5).crownWindowSeconds)
        settings.crownSensitivity = 9
        XCTAssertEqual(settings.sensitivity, 5, "Out-of-range values are clamped")
        XCTAssertEqual(WatchControlSettings.standard.sensitivity, 3)
    }

    func testPlanWithoutControlsStillDecodes() throws {
        var plan = WatchPlan(generatedAt: Date(timeIntervalSince1970: 100), units: .metric, coaching: CoachingConfig(), runs: [])
        XCTAssertNil(WatchPlan.decode(plan.encoded())?.controls)
        plan.controls = WatchControlSettings(doubleTap: .pauseResume, crown: .off)
        XCTAssertEqual(WatchPlan.decode(plan.encoded())?.controls?.doubleTap, .pauseResume)
    }
}

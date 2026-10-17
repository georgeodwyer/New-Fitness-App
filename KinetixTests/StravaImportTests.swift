import XCTest
import SwiftData
import KinetixSync
import TrainingEngine
@testable import Kinetix

@MainActor
final class StravaImportTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_792_049_400)

    private func activity(_ id: Int, _ sport: String, at offset: TimeInterval = 0, minutes: Int = 30, externalId: String? = nil,
                          heartRate: Double? = nil, polyline: String? = nil) -> StravaActivity {
        StravaActivity(id: id, name: "\(sport) \(id)", sportType: sport, startDate: start.addingTimeInterval(offset),
                       elapsedTime: minutes * 60, movingTime: minutes * 60 - 30, distance: sport == "Run" ? Double(minutes) * 180 : 0,
                       averageHeartrate: heartRate, maxHeartrate: heartRate.map { $0 + 20 }, externalId: externalId,
                       map: polyline.map { StravaActivity.Map(summaryPolyline: $0) })
    }

    func testPlanSkipsOwnUploadsKnownActivitiesAndDuplicates() {
        let kinetixRun = DateInterval(start: start.addingTimeInterval(86_400), duration: 1800)
        let plan = StravaImport.plan(
            activities: [
                activity(1, "Run"),                                             // new run: imported
                activity(2, "Run", at: 3600, externalId: "kinetix-ABC"),        // Kinetix's own upload
                activity(3, "Run", at: 7200),                                   // already imported (known id)
                activity(4, "Run", at: 86_400 + 60),                            // same time as a Kinetix run
                activity(5, "Ride", at: 10_800, minutes: 60),                  // load only
                activity(6, "WeightTraining", at: 20_000, minutes: 45)          // load only
            ],
            knownActivityIds: ["3"],
            kinetixSessions: [kinetixRun])
        XCTAssertEqual(plan.runs.map(\.id), [1])
        XCTAssertEqual(plan.workouts.map(\.kind), [.cycling, .strength])
        XCTAssertEqual(plan.workouts.first?.id, StravaImport.stableID(for: 5), "Re-importing replaces rather than adds")
        XCTAssertNotEqual(StravaImport.stableID(for: 5), StravaImport.stableID(for: 6))
    }

    func testImportedRunBecomesAKinetixRun() throws {
        let log = StravaService.runLog(from: activity(42, "Run", minutes: 30, heartRate: 150, polyline: "_p~iF~ps|U_ulLnnqC_mqNvxq`@"),
                                       maxHeartRate: 190)
        XCTAssertTrue(log.isImportedFromStrava)
        XCTAssertEqual(log.sourceTag, "From Strava")
        XCTAssertEqual(log.stravaActivityId, "42")
        XCTAssertEqual(log.durationSeconds, 1770, "Moving time")
        XCTAssertEqual(log.distanceMeters, 5400)
        XCTAssertTrue(log.isFinished)
        XCTAssertTrue(log.countsTowardsHistory)
        XCTAssertEqual(log.route.count, 3)
        XCTAssertEqual(log.route.last?.elapsed ?? 0, 1770, accuracy: 0.001)
        XCTAssertGreaterThan(log.effort, 1)
        XCTAssertEqual(log.load, SessionLoad.srpe(durationSeconds: 1770, effort: log.effort), accuracy: 0.001)
    }

    func testImportedRunsAreNeverExported() async throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let log = StravaService.runLog(from: activity(7, "Run"), maxHeartRate: nil)
        context.insert(log)
        try context.save()
        await ActivityExportService.export(run: log, in: context)
        XCTAssertNil(log.healthKitWorkoutId)
        XCTAssertEqual(log.stravaActivityId, "7")
    }

    func testHealthAndStravaCopiesOfAWorkoutCountOnce() {
        let ride = ExternalWorkout(id: UUID(), start: start, end: start.addingTimeInterval(3600), kind: .cycling, name: "Ride")
        let sameRide = ExternalWorkout(id: UUID(), start: start.addingTimeInterval(60), end: start.addingTimeInterval(3500),
                                       kind: .cycling, name: "Morning Ride")
        let walk = ExternalWorkout(id: UUID(), start: start.addingTimeInterval(600), end: start.addingTimeInterval(1800),
                                   kind: .walking, name: "Walk")
        let merged = ExternalWorkouts.merged([ride], [sameRide, walk])
        XCTAssertEqual(merged.map(\.name), ["Ride", "Walk"], "Different kinds at the same time both count")
    }

    func testLoadWorkoutsCombineSources() {
        let defaults = UserDefaults(suiteName: "StravaImportTests")!
        defaults.removePersistentDomain(forName: "StravaImportTests")
        let settings = IntegrationSettings(defaults: defaults)
        let ride = ExternalWorkout(id: UUID(), start: start, end: start.addingTimeInterval(3600), kind: .cycling, name: "Ride")
        settings.stravaWorkouts = [ride]
        XCTAssertEqual(settings.loadWorkouts.count, 1, "Strava workouts count even without Apple Health")
        settings.stravaImportEnabled = false
        XCTAssertTrue(settings.loadWorkouts.isEmpty)
    }
}

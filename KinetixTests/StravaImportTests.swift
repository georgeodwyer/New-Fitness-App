import XCTest
import SwiftData
import TrainingEngine
@testable import Kinetix

/// Kinetix only uploads to Strava; activities imported by earlier versions are removed.
@MainActor
final class StravaImportTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_792_049_400)

    func testImportedActivitiesAreRemoved() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let imported = RunLogModel(plannedSessionId: nil, startedAt: start)
        imported.importSourceRaw = "strava"
        imported.isFinished = true
        let own = RunLogModel(plannedSessionId: nil, startedAt: start)
        own.isFinished = true
        own.stravaActivityId = "123" // uploaded by Kinetix: stays
        context.insert(imported)
        context.insert(own)
        try context.save()

        let defaults = UserDefaults(suiteName: "StravaImportTests")!
        defaults.removePersistentDomain(forName: "StravaImportTests")
        let settings = IntegrationSettings(defaults: defaults)
        settings.stravaWorkouts = [ExternalWorkout(id: UUID(), start: start, end: start.addingTimeInterval(3600), kind: .cycling, name: "Ride")]
        settings.stravaLastImport = start

        StravaService(config: nil, useKeychain: false).removeImportedActivities(in: context, settings: settings)
        XCTAssertTrue(imported.isSoftDeleted)
        XCTAssertFalse(own.isSoftDeleted)
        XCTAssertTrue(settings.stravaWorkouts.isEmpty)
        XCTAssertNil(settings.stravaLastImport)
    }

    func testLoadWorkoutsComeFromAppleHealthOnly() {
        let defaults = UserDefaults(suiteName: "StravaImportTests.load")!
        defaults.removePersistentDomain(forName: "StravaImportTests.load")
        let settings = IntegrationSettings(defaults: defaults)
        let ride = ExternalWorkout(id: UUID(), start: start, end: start.addingTimeInterval(3600), kind: .cycling, name: "Ride")
        settings.stravaWorkouts = [ride]
        settings.healthEnabled = false
        XCTAssertTrue(settings.loadWorkouts.isEmpty, "Strava activities no longer count")
        settings.healthEnabled = true
        settings.externalWorkouts = [ride]
        XCTAssertEqual(settings.loadWorkouts.count, 1)
    }
}

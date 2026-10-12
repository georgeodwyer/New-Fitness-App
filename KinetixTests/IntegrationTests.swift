import XCTest
import SwiftData
import TrainingEngine
@testable import Kinetix

@MainActor
final class IntegrationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)
    private var containers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try Persistence.makeContainer(inMemory: true)
        containers.append(container)
        return container.mainContext
    }

    func testSettingsPersistPerDevice() throws {
        let suite = "IntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = IntegrationSettings(defaults: defaults)
        XCTAssertFalse(settings.healthEnabled)
        XCTAssertTrue(settings.stravaUploadRuns, "Runs upload by default once Strava is connected")
        XCTAssertFalse(settings.stravaUploadLifts)

        let sensor = UUID()
        settings.healthEnabled = true
        settings.heartRateSensorID = sensor
        settings.heartRateSensorName = "Polar H10"
        settings.externalWorkouts = [ExternalWorkout(id: UUID(), start: start, end: start.addingTimeInterval(1800), kind: .cycling, name: "Ride")]

        let reloaded = IntegrationSettings(defaults: defaults)
        XCTAssertTrue(reloaded.healthEnabled)
        XCTAssertEqual(reloaded.heartRateSensorID, sensor)
        XCTAssertEqual(reloaded.heartRateSensorName, "Polar H10")
        XCTAssertEqual(reloaded.externalWorkouts.first?.name, "Ride")

        reloaded.reset()
        XCTAssertNil(IntegrationSettings(defaults: defaults).heartRateSensorID)
    }

    func testOtherAppsWorkoutsCountTowardsLoadButNotTwice() throws {
        let context = try makeContext()
        let run = RunLogModel(plannedSessionId: nil, startedAt: start)
        run.durationSeconds = 1800
        run.finishedAt = start.addingTimeInterval(1800)
        run.isFinished = true
        run.effort = 5
        run.load = 150
        context.insert(run)

        let watchCopyOfRun = ExternalWorkout(id: UUID(), start: start.addingTimeInterval(30), end: start.addingTimeInterval(1790), kind: .run, name: "Run")
        let ride = ExternalWorkout(id: UUID(), start: start.addingTimeInterval(86_400), end: start.addingTimeInterval(86_400 + 3600), kind: .cycling, name: "Ride")
        let entries = DashboardService.loadEntries(runs: [run], lifts: [], external: [watchCopyOfRun, ride])
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.filter { $0.discipline == .crossTraining }.map(\.load), [240])
    }

    func testRunRecordsHeartRateSamples() throws {
        let context = try makeContext()
        let log = RunService.begin(planned: nil, title: "Easy run", simulated: true, in: context, now: start)
        var engine = RunEngine(structure: nil)
        _ = engine.start(at: start)
        for second in stride(from: 0, through: 30, by: 1) {
            let now = start.addingTimeInterval(Double(second))
            _ = engine.tick(at: now)
            engine.addHeartRate(140, at: now)
        }
        RunService.record(engine.summary(), into: log)
        let samples = StoredJSON.decode([HeartRateSample].self, from: log.heartRateData)
        XCTAssertEqual(samples?.count, 7)
        XCTAssertEqual(log.averageHeartRate, 140)
    }

    func testStravaDescriptions() throws {
        let context = try makeContext()
        let lift = StrengthLogModel(plannedSessionId: nil, startedAt: start)
        context.insert(lift)
        for index in 0..<3 {
            let set = SetLogModel(exerciseId: "barbell-back-squat", setIndex: index, targetReps: 5, targetWeightKg: 100)
            set.exerciseName = "Back Squat"
            set.progressionKey = "barbell-back-squat.main"
            set.completedAt = start
            set.session = lift
            context.insert(set)
        }
        let pullUp = SetLogModel(exerciseId: "pull-up", setIndex: 0, targetReps: 8, targetWeightKg: 0)
        pullUp.exerciseName = "Pull-up"
        pullUp.progressionKey = "pull-up.accessory"
        pullUp.exerciseOrder = 1
        pullUp.isBodyweight = true
        pullUp.completedAt = start
        pullUp.session = lift
        context.insert(pullUp)
        try context.save()

        XCTAssertEqual(StravaService.strengthDescription(lift, units: .metric),
                       "Back Squat: 3 × 5 @ 100 kg\nPull-up: 1 × 8\nPlanned and tracked by Kinetix.")

        let run = RunLogModel(plannedSessionId: nil, startedAt: start)
        run.targetedSeconds = 1000
        run.timeInTargetSeconds = 820
        run.effort = 7
        XCTAssertEqual(StravaService.runDescription(run), "Planned and coached by Kinetix. 82% of target time on pace. Effort 7/10.")
    }

    func testSimulatedRunsAreNeverExported() async throws {
        let context = try makeContext()
        let log = RunService.begin(planned: nil, title: "Run", simulated: true, in: context, now: start)
        log.isFinished = true
        log.finishedAt = start
        await ActivityExportService.export(run: log, in: context)
        XCTAssertNil(log.healthKitWorkoutId)
        XCTAssertNil(log.stravaActivityId)
    }
}
